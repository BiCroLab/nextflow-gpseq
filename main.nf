// Include samplesheet plugin
include { fromSamplesheet } from 'plugin/nf-validation'

// Get genome attributes
params.fasta = WorkflowMain.getGenomeAttribute(params, 'fasta')
params.fasta_index = WorkflowMain.getGenomeAttribute(params, 'fasta_index')
params.bwt2index = WorkflowMain.getGenomeAttribute(params, 'bowtie2')
params.mask_bed = WorkflowMain.getGenomeAttribute(params, 'mask_bed')

// Print pipeline info
log.info """\

		G P S E Q   P I P E L I N E
		===================================
		Samplesheet		: ${params.samplesheet}
		Outdir			: ${params.outdir}
		Run			: ${params.runid ? params.runid : params.outdir.replaceAll(".+\\/", "")}
		Reference		: ${params.genome ? params.genome : params.fasta.replaceAll(".+\\/", "")}
		Enzyme			: ${params.enzyme}
		Cutsite			: ${params.cutsite}
		Pattern			: ${params.pattern}
		"""
		.stripIndent()

// Prepare SNPsplit reference genome if the experiment is from a chimeric mouse model
process SNPSPLIT_PREPARE_GENOME {
	label ""
	tag "Preparing SNPsplit genome for ${reference}"
	
	container "https://depot.galaxyproject.org/singularity/snpsplit:0.6.0--hdfd78af_0"
	
	input:
		path fasta
		path vcf_file
		val strain
		
	output:
		path fasta
		
	script:
		"""
		SNPsplit_genome_preparation --reference_genome ${reference} \
                            --vcf_file ${vcf_file} \
                            --strain ${strain}
		"""
}

// Index the SNPsplit reference genome using bowtie2-index
process SNPSPLIT_INDEX_GENOME {
	label ""
	tag "Preparing SNPsplit genome for ${reference}"
	
	container "https://depot.galaxyproject.org/singularity/mulled-v2-ac74a7f02cebcfcc07d8e8d1d750af9c83b4d45a:a0ffedb52808e102887f6ce600d092675bf3528a-0"
	
	input:
		path fasta
		
	output:
		path bwt2index
		
	script:
		"""
		bowtie2-build ${reference} ${reference}
		"""
}

// Get file with all cutsite locations for given reference genome and enzyme combination
process GET_CUTSITES {
	label "process_single"
	tag "Getting cutsite locations for ${enzyme} in ${fasta.Name}"
	
	
	container "library://ljwharbers/gpseq/fastx-barber:0.0.4"
	
	input:
		path fasta
		val cutsite
		val enzyme
		
	output:
		path "${fasta.baseName}_${enzyme}_${cutsite}_sites.bed.gz"
	
	script:
		"""
		fbarber find_seq ${fasta} ${cutsite} --case-insensitive \\
		--global-name --output ${fasta.baseName}_${enzyme}_${cutsite}_sites.bed.gz
		"""
}

// Extract the barcode, cutsite and UMI information from reads
process EXTRACT {
	label "process_low"
	tag "fbarber extract on ${sample}"
 
	container "library://ljwharbers/gpseq/fastx-barber:0.0.4"
	publishDir "${params.outdir}/logs", mode: 'copy', pattern: "*.log"
 
	input:
		tuple val(sample), val(barcode), path(reads)
		val pattern
	output:
		tuple val(sample), path("hq_${sample}.fastq.gz"), emit: hq_extracted
		tuple val(sample), path("lq_${sample}.fastq.gz"), emit: lq_extracted
		tuple val(sample), path("noprefix_${sample}.fastq.gz"), emit: unmatched_extracted
		tuple val(sample), path("${sample}.log"), emit: log_extracted

	script:
		"""
		UMI_LENGTH=8
		CS_LENGTH=4
		BC_LENGTH=${barcode.size()}

		// todo: adjust input channels and make UMI_LENGTH and CS_LENGTH dynamically inferred

		pattern="umi\${UMI_LENGTH}bc\${BC_LENGTH}cs\${CS_LENGTH}"
 
		fbarber flag extract ${reads} hq_${sample}.fastq.gz \\
		 --filter-qual-output lq_${sample}.fastq.gz \\
		 --unmatched-output noprefix_${sample}.fastq.gz \\
		 --log ${sample}.log --pattern \${pattern} --simple-pattern \\
		 --flagstats bc cs --filter-qual-flags umi,30,.2 \\
		 --threads ${task.cpus} --chunk-size 200000
   		"""
}

// Filter reads checking for correct barcode and cutsite
process FILTER {
	label "process_low"
	tag "fbarber filter on ${sample}"

	container "library://ljwharbers/gpseq/fastx-barber:0.0.4"
	
	publishDir "${params.outdir}/logs", mode: 'copy', pattern: "*.log"
	
	input:
		tuple val(sample), val(barcode), path(hq_extracted)
		val cutsite
		
	output:
		tuple val(sample), path("filtered_${sample}.fastq.gz"), emit: filtered
		tuple val(sample), path("unmatched_${sample}.fastq.gz"), emit: unmatched
		tuple val(sample), path("${sample}_filtering.log"), emit: log_filtering
	
	script:
		"""
		fbarber flag regex ${hq_extracted} filtered_${sample}.fastq.gz \\
		--unmatched-output unmatched_${sample}.fastq.gz \\
		--log-file ${sample}_filtering.log \\
		--pattern "bc,^(?<bc>"${barcode}"){s<2}\$" "cs,^(?<cs>${cutsite}){s<2}\$" \\
		--threads ${task.cpus} --chunk-size 200000
		"""
}

// Align filtered fastq files to reference genome using bowtie2
process ALIGN {
	label "process_highcpu"
	tag "bowtie2 on ${sample}"
	
	container "https://depot.galaxyproject.org/singularity/mulled-v2-ac74a7f02cebcfcc07d8e8d1d750af9c83b4d45a:a0ffedb52808e102887f6ce600d092675bf3528a-0"
	
	publishDir "${params.outdir}/logs/", mode: 'copy', pattern: "*.log"
	
	input:
		tuple val(sample), path(filtered)
		path fasta
		path index
	
	output:
		tuple val(sample), path("${sample}.bam"), emit: bam
		path "${sample}_bowtie2.log", emit: log
	
	script:
		"""
		INDEX=`find -L ./ -name "*.rev.1.bt2" | sed "s/\\.rev.1.bt2\$//"`
    	[ -z "\$INDEX" ] && INDEX=`find -L ./ -name "*.rev.1.bt2l" | sed "s/\\.rev.1.bt2l\$//"`
    	[ -z "\$INDEX" ] && echo "Bowtie2 index files not found" 1>&2 && exit 1
		
		bowtie2 -x \$INDEX ${filtered} --very-sensitive -L 20 --score-min L,-0.6,-0.2 \\
		--end-to-end --reorder -p ${task.cpus} 2> "${sample}_bowtie2.log" | \\
		samtools sort --threads ${task.cpus} -o "${sample}.bam"
		"""
}

// Filter bamfile on quality score, chromosomes etc
process FILTER_BAM {
	label "process_medium"
	tag "filtering bam of ${sample}"
	
	container "https://depot.galaxyproject.org/singularity/sambamba:1.0--h98b6b92_0"
	
	input:
		tuple val(sample), path(bam)
		
	output:
		tuple val(sample), path("${sample}.filt.bam"), emit: filt_bam
		
	script:
		"""						 
		sambamba view ${bam} -f bam -F "mapping_quality>=30 and not secondary_alignment and \\
		not unmapped and not chimeric and ref_name!='chrM' and ref_name!='MT'" > ${sample}.filt.bam
		"""
}

// SNPsplit if the experiment is from a
process SNPSPLIT_SPLIT {
	label ""
	tag "Splitting bamfile on SNP positions of ${sample}"
	
	container "https://depot.galaxyproject.org/singularity/snpsplit:0.6.0--hdfd78af_0"
	
	input:
		tuple val(sample), path(bam)
		
	output:
		tuple val(sample), path("${sample}_genome1.filt.bam"), emit: filt_bam_1
		tuple val(sample), path("${sample}_genome2.filt.bam"), emit: filt_bam_2
		
	script:
		"""
		SNPsplit --weird --no_sort --snp_file ${params.snp_file} ${bam}
		"""
}

// Correct forward and reverse positions
process CORRECT_POS {
	label "process_medium"
	tag "Correcting forward and reverse base positions of ${sample}"
	
	container "https://depot.galaxyproject.org/singularity/mulled-v2-2948bee3b01472a1213e7d859fb1d41fe1db9fe4:3bb7859076ae5170dead8b24531eed649f8649e8-0" 
	
	input:
		tuple val(sample), path(bam)
		
	output:
		tuple val(sample), path("${sample}.forward.bed.gz"), path("${sample}.reverse.bed.gz"), emit: corrected_bed
	
	script:
		"""
		export TMPDIR=\$PWD
		sambamba view ${bam} -h -f bam -F "reverse_strand" | \\
		 convert2bed --input=bam - | \\
                 cut -f 1-4 | \\
                 sed 's/~/\t/g' | \\
                 cut -f 1,3,7,16 | \\
		 awk '\$3 !~ /N/' | \\
                 gzip > ${sample}.forward.bed.gz
		
		sambamba view ${bam} -h -f bam -F "not reverse_strand" | \\
   		 convert2bed --input=bam - | \\
                 cut -f 1-4 | \\
                 sed 's/~/\t/g' | \\
                 cut -f 1,2,7,16 | \\
		 awk '\$3 !~ /N/' | \\
                 gzip > ${sample}.reverse.bed.gz
		"""
}

// Group UMIs
process GROUP_UMIS {
	label "process_single"
	tag "Grouping UMIs of ${sample}"
	
	container "library://ljwharbers/gpseq/gpseq_pyenv:0.0.1"
	
	input:
		tuple val(sample), path(forward_bed), path(reverse_bed)
		
	output:
		tuple val(sample), path("${sample}.clean_umis.txt.gz"), emit: umi_clean
		
	script:
		"""
		group_umis.py ${forward_bed} ${reverse_bed} "${sample}.clean_umis.txt.gz" \\
		--compress-level 6 --len ${params.cutsite.length()}
		"""
}

// Assign UMIs to cutsite
process ASSIGN_UMIS {
	label "process_low"
	tag "Assigning UMIs to cutsite of ${sample}"
	
	container "library://ljwharbers/gpseq/gpseq_pyenv:0.0.1"
	
	input:
		tuple val(sample), path(umi_clean)
		path ref_cutsites
		
	output:
		tuple val(sample), path("${sample}_umi_atcs.txt.gz"), emit: umi_atcs
		
	script:
		"""
		umis2cutsite.py ${umi_clean} ${ref_cutsites} "${sample}_umi_atcs.txt.gz" --compress --threads ${task.cpus}
		"""
}

// Deduplicate UMIs
process DEDUPLICATE {
	label "process_medium"
	tag "Deduplicating UMIs of ${sample}"
	
	container "library://ljwharbers/gpseq/gpseq_renv:0.0.4"
	
	input:
		tuple val(sample), path(umi_atcs)
	
	output:
		tuple val(sample), path("${sample}_dedup.txt.gz"), emit: umi_dedup
		
	script:
		"""
		umi_dedupl.R ${umi_atcs} "${sample}_dedup.txt.gz" -c ${task.cpus} -r 10000
		"""
}

// Generate final bed file
process GENERATE_BED {
	label "process_low"
	tag "Generating final bed file of ${sample}"
	
	// Publish
	publishDir params.outdir, mode: 'copy'
	
	input: 
		tuple val(sample), path(umi_dedup)
	
	output:
		tuple val(sample), path("${sample}.bed.gz"), emit: bed
		
	script:
		"""
		zcat ${umi_dedup} | awk 'BEGIN{{FS=OFS="\t"}}{{print \$1, \$2, \$2, "pos_"NR, \$4}}' | sed 's/ //g' | gzip > ${sample}.bed.gz
		"""
}

// Count Fastqs reads
process COUNT_FILTERS {
	label "process_low"
	tag "Counting the number of reads/umis after each filtering step of ${sample}"
	
	container "https://depot.galaxyproject.org/singularity/samtools:1.8--4"
		
	input:
		tuple val(sample),
					val(condition),
					// Fastqs
					path(fastq),
					path(hq_extracted),
					path(lq_extracted),
					path(unmatched_extracted),
					path(filtered),
					path(unmatched),
					// Bams
					path(bam),
					path(filt_bam),		
					// UMIs
					path(umi_forward),
					path(umi_reverse),
					path(dedup)
	output:
		path("${sample}_filter_counts.txt"), emit: fastq_counts
		
	script:
		"""
		touch ${sample}_filter_counts.txt
		# Get headers
		echo sample\tcondition\tfilter\tcount >> ${sample}_filter_counts.txt
		
		# Fastq counts
		echo ${sample}\t${condition}\tinput\t\$(zcat ${fastq} | echo \$((`wc -l`/4))) >> ${sample}_filter_counts.txt
		echo ${sample}\t${condition}\thq_extracted\t\$(zcat ${hq_extracted} | echo \$((`wc -l`/4))) >> ${sample}_filter_counts.txt
		echo ${sample}\t${condition}\tlq_extracted\t\$(zcat ${lq_extracted} | echo \$((`wc -l`/4))) >> ${sample}_filter_counts.txt
		echo ${sample}\t${condition}\tnoprefix_extracted\t\$(zcat ${unmatched_extracted} | echo \$((`wc -l`/4))) >> ${sample}_filter_counts.txt
		echo ${sample}\t${condition}\tprefix_match\t\$(zcat ${filtered} | echo \$((`wc -l`/4))) >> ${sample}_filter_counts.txt
		echo ${sample}\t${condition}\tprefix_unmatched\t\$(zcat ${unmatched} | echo \$((`wc -l`/4))) >> ${sample}_filter_counts.txt
		
		# Bam counts
		echo ${sample}\t${condition}\taligned_reads\t\$(samtools view ${bam} -c) >> ${sample}_filter_counts.txt
		echo ${sample}\t${condition}\thq_reads\t\$(samtools view ${filt_bam} -c) >> ${sample}_filter_counts.txt
		
		# UMI counts
		echo ${sample}\t${condition}\ttotal_umis\t\$(zcat ${umi_forward} ${umi_reverse} | echo \$(wc -l)) >> ${sample}_filter_counts.txt
		echo ${sample}\t${condition}\tdedup_umis\t\$(zcat ${dedup} | echo \$(awk -F'\t' '{sum+=\$4;}END{print sum;}')) >> ${sample}_filter_counts.txt
		"""
}

// Generate summary table and plots
process GENERATE_SUMMARY_PLOTS {
	label "process_low"
	tag "Generating summary plots of all samples"
	
	container "library://ljwharbers/gpseq/gpseq_renv:0.0.4"	
	
	publishDir params.outdir, mode: 'copy'
	
	input:
		path counts
		
	output:
		path 'summary_plot.pdf'
		path 'summary_table.tsv'
		
	script:
		"""
		summary.R --input ${counts} --output_plot summary_plot.pdf --output_table summary_table.tsv
		"""
}

// Generate metadata for GPSeq score calculation
process GENERATE_GPSEQ_METADATA {
	label "process_low"
	tag "Generating metadata for GPSeq score calculation"
	
	container "library://ljwharbers/gpseq/gpseq_renv:0.0.4"
	
	publishDir params.outdir, mode: 'copy'
	
	input:
		val(conditions)
		val(samples)
		path(beds)
		val(runid)
	
	output:
		path 'gpseq_metadata.tsv'
	
	script:
		conditions = conditions.collect { "$it" }.join(' ')
		samples = samples.collect { "$it" }.join(' ')
		runid = runid.collect { "$it" }.join(' ')

		"""
		generateMetadata.R --runs ${runid} --conditions ${conditions} --samples ${samples} --filepaths ${beds} --output gpseq_metadata.tsv
		"""
}

// Get chromsize from .fai
process GET_CHROMSIZES {
	label "process_single"
	tag "getting chromsize from ${fasta_index.Name}"
	
	input:
		path fasta_index
		
	output:
		path "${fasta_index.baseName}.chromsizes"
	
	script:
		"""
		cut -f 1,2 ${fasta_index} > ${fasta_index.baseName}.chromsizes
		"""
}

// Calculate GPSeq score
process CALCULATE_GPSEQ_SCORE {
	label "process_medium"
	tag "Calculating GPSeq score"
	
	container "library://ljwharbers/gpseq/gpseq_renv:0.0.3"
	
	publishDir params.outdir, mode: 'copy'
	
	input:
		path beds
		path metadata
		path chromsizes
		path mask_bed
		path site_bed
		val binsizes
		val normalization
		val bed_outlier_tag
		val score_outlier_tag
		val site_domain
	
	output:
		path 'gpseq_scores/*'
		path 'gpseq_scores/gpseq-radical.out.rds' , emit: score_rds
	
	script:
		def sitebed_args = ""
		sitebed_args = site_domain == "universe" ? "--site-bed ${site_bed}" : "" 
		"""
		gpseq-radical.R ${metadata} gpseq_scores --bin-tags ${binsizes} --bed-outlier-tag ${bed_outlier_tag}  \
		--score-outlier-tag ${score_outlier_tag} --cinfo-path ${chromsizes} --normalize-by ${normalization} \
		--site-domain ${site_domain} --mask-bed ${mask_bed} --chromosome-wide --threads ${task.cpus} ${sitebed_args}
		"""
}

// Plot Pizza plots
process PLOT_PIZZA {
	label "process_low"
	tag "Plotting pizza plots"
	
	container "library://ljwharbers/gpseq/gpseq_renv:0.0.4"
	
	publishDir "${params.outdir}/gpseq_scores", mode:  'copy'
	
	input:
		path scores
	
	output:
		path 'pizza_plot*.png'
	
	script:
		"""
		pizza_plot.R --input ${scores} --output \$PWD 
		"""
}

// Plot ideogram plots
process PLOT_IDEOGRAM {
	label "process_low"
	tag "Plotting ideogram plots"
	
	container "library://ljwharbers/gpseq/gpseq_renv:0.0.4"
	
	publishDir "${params.outdir}/gpseq_scores", mode: 'copy'
	
	input:
		path scores
	
	output:
		path 'ideogram_plot*.png'
	
	script:
		"""
		ideogram_plot.R --input ${scores} --output \$PWD 
		"""
}

// Run Fastqc on initial fastq files
process  FASTQC {
	label "process_medium"
	tag "FASTQC on ${sample}"

	container "https://depot.galaxyproject.org/singularity/fastqc:0.11.9--0"
	
	input:
		tuple val(sample), path(reads)
	
	output:
		path "fastqc_${sample}_logs"
	
	script:
		"""
		mkdir fastqc_${sample}_logs
		fastqc -o fastqc_${sample}_logs -f fastq -q ${reads}
		"""
}

// Get report from MultiQC
process MULTIQC {
	label "process_medium"
	tag "MultiQC on all samples"
	
	container "https://depot.galaxyproject.org/singularity/multiqc:1.15--pyhdfd78af_0"
	
	publishDir params.outdir, mode: 'copy'

	input:
		path '*'

	output:
		path 'multiqc_report.html'

	script:
		"""
		multiqc .
		"""
}

workflow {
	// Create channel from input samplesheet
	Channel.fromSamplesheet("samplesheet")
		.multiMap { sample, fastq, barcode, condition -> 
							 sample_ch: sample
							 input_ch: tuple(sample, fastq)
							 barcode_ch: tuple(sample, barcode)
							 condition_ch: tuple(sample, condition)}
		.set { samplesheet }
	
	// Run workflow
	
        // Initial QC and generating cutsites
        fastqc_ch = FASTQC(samplesheet.input_ch) // FASTQC
        cutsites_ch = GET_CUTSITES(params.fasta, params.cutsite, params.enzyme) // Getting cutsite locations

	// Main preprocessing pipeline
	extract_ch = samplesheet.input_ch
                 .join(samplesheet.barcode_ch)
                 .map { sample, reads, barcode -> tuple(sample, barcode, reads) }
                 .set { extract_input }

        extract_ch = EXTRACT(extract_input, params.pattern) // Extracting barcode, cutsite and UMI

	filter_ch = FILTER(samplesheet.barcode_ch.join(extract_ch.hq_extracted), params.cutsite) // Filtering reads
	align_ch = ALIGN(filter_ch.filtered, params.fasta, params.bwt2index) // Aligning reads
	filterbam_ch = FILTER_BAM(align_ch.bam) // Filtering bamfile
	correctpos_ch = CORRECT_POS(filterbam_ch.filt_bam) // Correcting forward and reverse positions
	clean_ch = GROUP_UMIS(correctpos_ch.corrected_bed) // Grouping UMIs
	atcs_ch = ASSIGN_UMIS(clean_ch.umi_clean, cutsites_ch) // Assigning UMIs to cutsite
	dedup_ch = DEDUPLICATE(atcs_ch.umi_atcs) // Deduplicating UMIs
	bed_ch = GENERATE_BED(dedup_ch.umi_dedup) // Generating final bed file
	MULTIQC(align_ch.log.mix(fastqc_ch).collect()) // MultiQC
	
	// Generating plots and summary table
	// Mixing all channels and grouping by sample ID
	samplesheet.condition_ch
		.join(samplesheet.input_ch)
		.join(extract_ch.hq_extracted)
		.join(extract_ch.lq_extracted)
		.join(extract_ch.unmatched_extracted)
		.join(filter_ch.filtered)
		.join(filter_ch.unmatched)
		.join(align_ch.bam)
		.join(filterbam_ch.filt_bam)
		.join(correctpos_ch.corrected_bed)
		.join(dedup_ch.umi_dedup)
		.set { countfilter_ch }

	counts_ch = COUNT_FILTERS(countfilter_ch) // Counting filters

	// Collect counts and run plotting
	GENERATE_SUMMARY_PLOTS(counts_ch.collect()) // Generating summary plots
	
	// Getting metadata file for GPSeq score calculations
	run_ch = Channel.of(params.runid ? params.runid : params.outdir)
	meta_ch = samplesheet.condition_ch
				.join(bed_ch)
				.combine(run_ch)
				.multiMap { sample, condition, bed, runid -> 
						sample: sample
						condition: condition
						bed: bed
						run: runid
				}
	score_meta = GENERATE_GPSEQ_METADATA(
		meta_ch.condition.collect(),
		meta_ch.sample.collect(),
		meta_ch.bed.collect(),
		meta_ch.run.collect()
	)
	
	// Get chromsizes
	chromsize_ch = GET_CHROMSIZES(params.fasta_index) // Getting chromsize from .fai

	// Calculating GPseq score
	gpseq_score = CALCULATE_GPSEQ_SCORE(meta_ch.bed.collect(), score_meta, chromsize_ch,
																			params.mask_bed, cutsites_ch, params.binsizes,
																			params.normalization, params.bed_outlier_tag,
																			params.score_outlier_tag, params.site_domain)
	
	// Plotting
	PLOT_PIZZA(gpseq_score.score_rds) // Plotting pizza plots
	//PLOT_IDEOGRAM(gpseq_score.score_rds) // Plotting ideogram plots
}

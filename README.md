## Nextflow pipeline for processing of GPSeq data

Genomic loci positioning by sequencing ([GPSeq](https://doi.org/10.1038/s41587-020-0519-y)): genome-wide method for inferring distances to the nuclear lamina all along the nuclear radius. 

<br>

### Getting Started
The whole pipeline can be cloned in your current working directory with:  
```
git clone https://github.com/BiCroLab/nextflow-gpseq
cd nextflow-gpseq
```

### Requirements

`conda create -n nextflow -c conda-forge -c bioconda nextflow=23.10.0 singularity=3.8*`

- nextflow (tested onversion 23.10 or higher)
- singularity (tested on version 3.8.6)

To test the pipeline with default settings and a test dataset: `nextflow run main.nf -profile test`  

<br>


### Running the pipeline with your own dataset

<br> 

1. Make a [`samplesheet.csv`](/assets/samplesheet.csv) containing the following columns: `sample,fastq,barcode,condition`.
   <br>The file should be comma separated and sorted by digestion time-point in seconds.

<br>

2. Check and adjust required settings in [`nextflow.config`](/nextflow.config) and [`igenomes.config`](/nextflow-gpseq/conf/igenomes.config).

<br>

3. Run the pipeline with the following command: <br>
 
   ```
   nextflow run main.nf --samplesheet /path/to/samplesheet.csv --outdir /path/to/results --fasta /path/to/reference.fa --bwt2index /path/to/bowtie2/index/folder -resume
   ```
<br>

---

### General Settings:

| Setting | Description |
| ---- | --- |
| `enzyme` / `cutsite`  | enzyme name (e.g. `DpnII`) and recognition motif (e.g. `GATC`)  |
| `binsizes` | list of comma-separated binsizes for calculating GPSeq scores; <br> formula: `window:smoothing`: `"1e+05:1e+05,1e+05:1e+04,5e+04:5e+04"` |
| `normalization` | data normalization by library / chromosome (`"lib"` / `"chrom"`) <br><br> `"lib"`: each experiment is normalized based on its total read count<br>`"chrom"`: normalization is applied independently for each chromosome | 
| `site_domain` | param affecting which restriction sites are considered for computing score <br> default value is `"universe"`; also see: `"separate"`/`"union"`<br><br>for a detailed explanation about all existing `site_domain` settings,<br>please refer to the supplementary information of our [GPSeq paper](https://doi.org/10.1038/s41587-020-0519-y). | 
| `score_outlier_tag` | setting to filter out outliers (default: `"iqr:1.5"`) |
| `bed_outlier_tag`  | setting to filter out outliers (default: `"chisq:0.01"`) | 

<br>

### Genome Settings:

Genome-related settings can be modified from [`igenomes.config`](/nextflow-gpseq/conf/igenomes.config):

| Setting | Description | 
| --- | --- |
| fasta | path to reference `genome.fa` genome sequence  |
| fasta_index | path to corresponding `genome.fa.fai` genome index |
| bowtie2 | path to directory containing bowtie2 index |
| mask_bed | path to bed file containing regions to be masked | 

<br>  

<!---
#### Memory Settings / Performance
--->  

---

### Outputs






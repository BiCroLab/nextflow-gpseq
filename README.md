## Nextflow pipeline for processing of GPSeq data

Check here the original [GPSeq paper](https://doi.org/10.1038/s41587-020-0519-y).

<br>

### Requirements
- nextflow (tested onversion 23.10 or higher)
- singularity (tested on version 3.8.6)

`conda create -n nextflow -c conda-forge -c bioconda nextflow=23.10.0 singularity=3.8*`

<br>

<!---

If you don't have conda installed yet you can install and initialize it in the following way:  
```
mkdir -p ~/miniconda3
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh
bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
rm -rf ~/miniconda3/miniconda.sh
~/miniconda3/bin/conda init bash
```

You can then activate the environment by running:  
`conda activate nextflow`

---> 
 


### Getting Started
The whole pipeline can be cloned in your current working directory with:  
```
git clone https://github.com/BiCroLab/nextflow-gpseq
cd nextflow-gpseq
```

To test the pipeline with default settings and a test dataset: `nextflow run main.nf -profile test`  

<br>

### Running the pipeline with your own dataset
To run the pipeline with your own dataset, there are a few steps to take.

1. Make a [`samplesheet.csv`](/assets/samplesheet.csv). An example samplesheet is located inside the repository `/assets/samplesheet.csv`. This must be a comma separated file that consists of the following columns: `sample,fastq,barcode,condition`. The file should be sorted by digestion time-point in seconds. 

2. Adjust `nextflow.config`.  There are some default parameters used and specified in the configuration file and, depending on your most common usecase, it is advisable to change some of these defaults.

   #### General Settings:

   | Setting | Description |
   | ---- | --- |
   | `enzyme`  | enzyme name (e.g. `DpnII`) |
   | `cutsite` | enzyme recognition motif (e.g. `GATC`) | 
   | `binsizes` | list of comma-separated binsizes for calculating GPSeq scores; <br> formula: `window:smoothing`: `"1e+05:1e+05,1e+05:1e+04,5e+04:5e+04"` |
   | `score_outlier_tag` | setting to filter out outliers (default: `"iqr:1.5"`) |
   | `bed_outlier_tag`  | setting to filter out outliers (default: `"chisq:0.01"`) | 
   | `normalization` | normalization by library / chromosome (`"lib"` / `"chrom"`) | 
   | `site_domain` | parameter affecting which RE sites are considered for computing score <br> users can choose between `"universe"`/`"separate"` | 

   #### Genome Settings:

* If you will mostly run GPSeq on human, you can write the path to your own local reference file and bowtie2 index in the config file under `fasta` and `bwt2index`. However, I recommend using the iGenomes reference files (described further down).
  

   #### Memory Settings: 
   






<!---

   * Check `max_memory` and `max_cpus`. It is important that these do not go above your system values.
   
Following this you can either change the default parameters in the `nextflow.config` file or supply the parameters related to your own dataset in the command you type. I suggest that you change parameters that won't change much between runs in the `nextflow.config` file, while you specify parameters such as `input` and `output` through the command line.


   * Go over other parameters defined within the `params { }` section in the config file and change whatever you feel fit.  

   
An example command to run this on your own data could be:  
`nextflow run main.nf --samplesheet path/to/samplesheet.csv --outdir path/to/results --fasta path/to/reference.fa --bwt2index /path/to/bowtie2/index/folder`

If you do not specify a fasta file and bowtie2 index, you can specify the reference genome you want to use and it will download it from an AWS s3 bucket. For example in the following way:  
`nextflow run main.nf --samplesheet path/to/samplesheet.csv --outdir path/to/results --genome GRCh38`

Downloading the fasta file and index might be slow so you can also download the files that you would need through using this tool: https://ewels.github.io/AWS-iGenomes/ Note: you need `aws` tool for this. Once you've downloaded the reference and index files you need you can change the `igenomes_base` parameter in `nextflow.config` and it will take the fasta/index files from there instead of downloading it through nextflow.

Finally, if you want to resume canceled or failed runs, you can add the tag `-resume`. Usually, I always use this tag irregardless of if I run something for the first time or if I am resuming a run.
---> 

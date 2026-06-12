<!-- dx-header -->
# AmazingApp (DNAnexus Platform App)
This app provides an automated solution for handling Ensembl (1-22/X/Y/MT) and UCSC (chr1-22/X/Y/MT) chromosome naming differences within BAM files on the DNAnexus platform.

## What does this app do?
eggd_chr_prefix modifies the metadata headers of alignment files (BAMs) to either add or remove the chr prefix from chromosome sequence names (e.g., converting 1 to chr1, or chrX to X). It utilizes samtools reheader to swiftly apply these structural alterations without requiring a computationally expensive full realignment of the data. Finally, it automatically generates the required accompanying coordinate index (.bai) files.

## What are the inputs?
- input_file (file, optional): A single .bam file to be processed.
- input_file_array (array of files, optional): A specific list of multiple .bam files.
- input_folder (string, optional): A DNAnexus project folder path (e.g., /data/cohort_bams/). The app will automatically discover and process all .bam files within this directory.
- mode (string, required): The directional prefix edit mode. Defaults to add_chr.
    - Select add_chr to convert formats to standard UCSC (e.g., 1-22 → chr1-22, X → chrX, MT → chrM).
    - Select remove_chr to convert formats to standard Ensembl (e.g., chr1-22 → 1-22, chrX → X, chrM → MT).
 
Note: If none data are provided (input_file, input_file_array, or input_folder), the script will run default to project root "/" and search any *.bam files under this root.

## What are the outputs?
- output_files (array of files): The resulting .bam files with modified headers. They are dynamically named using _chr or _no_chr suffixes based on the selected mode to prevent overwriting original data.
- output_indices (array of files): The corresponding .bai index files for the newly modified BAMs.

## How to run this app from command line?
```
Example A: Running on a single file
dx run eggd_chr_prefix \
  -i input_file="project-Fkb...:file-Fxyz..." \
  -i mode="add_chr"

Example B: Running on a whole folder of BAMs (Auto-scan all *.bam files)
dx run eggd_chr_prefix \
  -i input_folder="/my_data/bams/" \ #if the folder input is empty, default to project root "/"
  -i mode="remove_chr"

```

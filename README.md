<!-- dx-header -->
# eggd_chr_prefix
This app provides an automated solution for handling Ensembl (1-22/X/Y/MT) and UCSC (chr1-22/X/Y/MT) chromosome-naming differences in BAM files on the DNAnexus platform.

## What does this app do?
eggd_chr_prefix modifies the metadata headers of alignment files (BAMs) to either add or remove the chr prefix from chromosome sequence names (e.g., converting 1 to chr1, or chrX to X). It utilises samtools reheader to these alterations and automatically generates the required accompanying coordinate index (.bai) files.

## What are the inputs?
- input_file (file, optional): A single .bam file to be processed.
- input_file_array (array of files, optional): A specific list of multiple .bam files.
- mode (string, required): The directional prefix edit mode. Defaults to add_chr.
    - Select add_chr to convert formats to standard UCSC (e.g., 1-22 → chr1-22, X → chrX, MT → chrM).
    - Select remove_chr to convert formats to standard Ensembl (e.g., chr1-22 → 1-22, chrX → X, chrM → MT).

## What are the outputs?
- output_files (array of files): The resulting .bam files with modified headers. They are dynamically named using add_chr or _remove_chr suffixes based on the selected mode to prevent overwriting original data.
- output_indices (array of files): The corresponding .bai index files for the newly modified BAMs.

Note: if the file is already in '$mode' format. No new files are created.

## How to run this app from the command line?
```bash
Example A: Running on a single file:
dx run eggd_chr_prefix \
  -iinput_file="project-Fkb...:file-Fxyz..." \
  -imode="add_chr"

Example B: Running on an array of input files:
dx run eggd_chr_prefix \
  -iinput_file_array="project-Fkb...:file-Fxyz..." \
  -iinput_file_array="project-Fkb...:file-Fxyz..." \
  -imode="remove_chr"

```

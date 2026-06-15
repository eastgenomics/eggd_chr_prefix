#!/bin/bash
# eggd_app

# Exit at any point if there is any error and output each line as it is executed (for debugging)
# -e = exit on error; -x = output each line that is executed to log; -o pipefail = throw an error if there's an error in pipeline
set -e -o pipefail

main() {
    local mode="${mode:-add_chr}" # Defaults to add_chr if no mode is specified
    echo "Starting eggd_chr_prefix execution..."
    echo "Selected Mode: '$mode'"
    
    # If no inputs at all are provided, default to project root "/"
    if [ -z "$input_file" ] && [ -z "$input_file_array" ] && [ -z "$input_folder" ]; then
        echo "No specific inputs provided. Defaulting input_folder to project root './'."
        input_folder="./"
    fi

    # 1. Gather Inputs
    local bam_files=()
    
    if [ -n "$input_file" ]; then
        bam_files+=("$input_file")
    fi

    if [ -n "$input_file_array" ]; then
        bam_files+=("${input_file_array[@]}")
    fi

    if [ -n "$input_folder" ]; then
    # Find all BAMs in the specified folder path
    while read -r file; do
        bam_files+=("$file")
    done < <(find "$input_folder" -maxdepth 1 -name "*.bam")
    fi

    if [ ${#bam_files[@]} -eq 0 ] || [ "${bam_files[0]}" == "*.bam" ]; then
    echo "Error: No target BAM files found."
    exit 1
    fi

    echo "Total files selected: ${#bam_files[@]}"


    # 2. Main Execution

    for BAM in "${bam_files[@]}"; do
    # Extract folder path and base filename
    local DIR_NAME=$(dirname "$BAM")
    if [ -n "$output_folder" ]; then
        echo "Custom Output Path: '$output_folder'"
        local TARGET_DIR="$output_folder"
        mkdir -p "$TARGET_DIR"
    else
        echo "Output Path: (Original Input Folders)"
        local TARGET_DIR=DIR_NAME
    fi
    local BASE_NAME=$(basename "$BAM" .bam) 
    local ORIG_HEADER="${DIR_NAME}/${BASE_NAME}_orig_header.sam"
    local TEMP_HEADER="${DIR_NAME}/${BASE_NAME}_header.sam"
    local OUTPUT_BAM
    local sed_cmd



    # Swap sed logic based on mode
        case "$mode" in
            "add_chr")
                sed_cmd='s/\tSN:\([0-9][0-9]*\)\t/\tSN:chr\1\t/g; s/\tSN:X\t/\tSN:chrX\t/g; s/\tSN:Y\t/\tSN:chrY\t/g; s/\tSN:MT\t/\tSN:chrM\t/g'
                OUTPUT_BAM="${TARGET_DIR}/${BASE_NAME}_chr.bam"
                ;;

            "remove_chr")
                sed_cmd='s/\tSN:chr\([0-9][0-9]*\)\t/\tSN:\1\t/g; s/\tSN:chrX\t/\tSN:X\t/g; s/\tSN:chrY\t/\tSN:Y\t/g; s/\tSN:chrM\t/\tSN:MT\t/g'
                OUTPUT_BAM="${TARGET_DIR}/${BASE_NAME}_no_chr.bam"
                ;;

            *)
                echo "Error: Unexpected execution mode runtime state '$mode'."
                echo "Valid options are: 'add_chr' or 'remove_chr'."
                exit 1
                ;;
        esac
        
        echo "=== Reheadering: $BASE_NAME ==="
        echo "Input BAM: $BAM"
        
        # Extract and modify the header and compare the old one
        samtools view -H "$BAM" > "$ORIG_HEADER"
        sed "$sed_cmd" "$ORIG_HEADER" > "$TEMP_HEADER"
        
        if cmp -s "$ORIG_HEADER" "$TEMP_HEADER"; then
            echo "Notice: File is already in '$mode' format. No changes needed."
            echo "Skipping BAM creation."
        else
            echo "Header before:"
            grep "^@SQ" "$ORIG_HEADER" | head -3 || true

           echo "Header after:" 
            grep "^@SQ" "$TEMP_HEADER" | head -3 || true
        
            # Reheader into the new BAM
            samtools reheader "$TEMP_HEADER" "$BAM" > "$OUTPUT_BAM"
        
            echo "Indexing..."
            samtools index "$OUTPUT_BAM"
        
            echo "Verifying chr prefix in new BAM:"
            samtools view -H "$OUTPUT_BAM" | grep "^@SQ" | head -5 || true
        fi
        
        # Clean up the temporary header file
        rm -f "$ORIG_HEADER" "$TEMP_HEADER"
        echo "Done: $BASE_NAME"
    done

    echo "Success: eggd_chr_prefix job completed."
}

# Execute the main function
main "$@"
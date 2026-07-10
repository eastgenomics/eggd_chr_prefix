#!/bin/bash
# eggd_app

# Exit at any point if there is any error and output each line as it is executed (for debugging)
# -e = exit on error; -x = output each line that is executed to log; -o pipefail = throw an error if there's an error in pipeline
set -e -x -o pipefail

main() {
    dx-download-all-inputs --parallel

    local mode="${mode:-add_chr}" # Defaults to add_chr if no mode is specified
    local single_mode=false
    echo "Starting eggd_chr_prefix execution..."
    echo "Selected Mode: '$mode'"

    # 1. Gather Inputs

    # Single-file mode (eggd_atlas_cnv workflow stage 0): one BAM in -> one BAM + index out,
    # with PASSTHROUGH when the header is already in the target format (never emit nothing).

    local bam_files=()
    local output_bam
    local output_bai

    if [ -n "${input_bam:-}" ]; then
        local_bam="/home/dnanexus/in/input_bam/$(dx describe "$input_bam" --name)"
        single_mode=true
        bam_files+=("$local_bam")
        mkdir -p inputs /home/dnanexus/out/output_bam /home/dnanexus/out/output_bai
    fi

    if [ -n "${input_bam_array:-}" ]; then
        for i in "${!input_bam_array[@]}"; do
            file_id="${input_bam_array[$i]}"
            bam_name="$(dx describe "$file_id" --name)"
            local_bam="/home/dnanexus/in/input_bam_array/${i}/${bam_name}"
            bam_files+=("$local_bam")
            mkdir -p inputs /home/dnanexus/out/output_files /home/dnanexus/out/output_indices 
        done
    fi

    if [ ${#bam_files[@]} -eq 0 ] || [ "${bam_files[0]}" == "*.bam" ]; then
    echo "Error: No target BAM files found."
    exit 1
    fi

    if [ "$single_mode" = true ] && [ ${#bam_files[@]} -gt 1 ]; then
        echo "Error: Provide either input_bam or input_bam_array, not both."
        exit 1
    fi
    echo "Total files selected: ${#bam_files[@]}"


    # 2. Main Execution
    for local_bam in "${bam_files[@]}"; do
    # Extract folder path and base filename
        local base_name="$(basename "$local_bam" .bam)"
        local orig_header="inputs/${base_name}_orig_header.sam"
        local temp_header="inputs/${base_name}_header.sam"
        local sed_cmd
        if [ "$single_mode" = true ]; then
            output_bam="/home/dnanexus/out/output_bam/${base_name}_$mode.bam"
            output_bai="/home/dnanexus/out/output_bai/${base_name}_$mode.bam.bai"
        else
            output_bam="/home/dnanexus/out/output_files/${base_name}_$mode.bam"
            output_bai="/home/dnanexus/out/output_indices/${base_name}_$mode.bam.bai"
        fi


    # Swap sed logic based on mode
        case "$mode" in
            "add_chr")
                sed_cmd='s/\tSN:\([0-9][0-9]*\)\t/\tSN:chr\1\t/g; s/\tSN:X\t/\tSN:chrX\t/g; s/\tSN:Y\t/\tSN:chrY\t/g; s/\tSN:MT\t/\tSN:chrM\t/g'
                ;;

            "remove_chr")
                sed_cmd='s/\tSN:chr\([0-9][0-9]*\)\t/\tSN:\1\t/g; s/\tSN:chrX\t/\tSN:X\t/g; s/\tSN:chrY\t/\tSN:Y\t/g; s/\tSN:chrM\t/\tSN:MT\t/g'
                ;;

            *)
                echo "Error: Unexpected execution mode runtime state '$mode'."
                echo "Valid options are: 'add_chr' or 'remove_chr'."
                exit 1
                ;;
        esac

        echo "=== Reheadering: $base_name ==="
        echo "Input BAM: $base_name"

        # Extract and modify the header and compare the old one
        samtools view -H "$local_bam" > "$orig_header"
        sed "$sed_cmd" "$orig_header" > "$temp_header"

        if cmp -s "$orig_header" "$temp_header"; then
            echo "Notice: File is already in '$mode' format - passthrough."
            cp "$local_bam" "$output_bam"
        else
            echo "Header before:"
            grep "^@SQ" "$orig_header" | head -3 || true

           echo "Header after:"
            grep "^@SQ" "$temp_header" | head -3 || true

            # Reheader into the new BAM
            samtools reheader "$temp_header" "$local_bam" > "$output_bam"
        fi

        echo "Indexing..."
        samtools index "$output_bam" "$output_bai"

        echo "Verifying chr prefix in new BAM:"
        samtools view -H "$output_bam" | grep "^@SQ" | head -5 || true
        # Clean up the temporary header file
        rm -f "$orig_header" "$temp_header"
        echo "Done: $base_name"
    done


    echo "Uploading outputs..."
    dx-upload-all-outputs --parallel
    echo "Success: eggd_chr_prefix job completed."
}

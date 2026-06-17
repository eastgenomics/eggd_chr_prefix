#!/bin/bash
# eggd_app

# Exit at any point if there is any error and output each line as it is executed (for debugging)
# -e = exit on error; -x = output each line that is executed to log; -o pipefail = throw an error if there's an error in pipeline
set -e -x -o pipefail

main() {
    local mode="${mode:-add_chr}" # Defaults to add_chr if no mode is specified
    echo "Starting eggd_chr_prefix execution..."
    echo "Selected Mode: '$mode'"
    mkdir -p inputs outputs

    # 1. Gather Inputs
    local bam_files=()

    if [ -n "$input_file" ]; then
        bam_files+=("$input_file")
    fi

    if [ -n "$input_file_array" ]; then
        bam_files+=("${input_file_array[@]}")
    fi

    if [ ${#bam_files[@]} -eq 0 ] || [ "${bam_files[0]}" == "*.bam" ]; then
    echo "Error: No target BAM files found."
    exit 1
    fi

    echo "Total files selected: ${#bam_files[@]}"


    # 2. Main Execution

    for file_id in "${bam_files[@]}"; do
    # Extract folder path and base filename
        local bam_name
        bam_name="$(dx describe "$file_id" --name)"
        local local_bam="inputs/${bam_name}"
        dx download "$file_id" -o "$local_bam" -f
        local base_name
        base_name="$(basename "$local_bam" .bam)"
        local orig_header="inputs/${base_name}_orig_header.sam"
        local temp_header="inputs/${base_name}_header.sam"
        local output_bam="outputs/${base_name}_$mode.bam"
        local output_bai="${output_bam}.bai"
        local sed_cmd

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

        echo "=== Reheadering: $bam_name ==="
        echo "Input BAM: $base_name"

        # Extract and modify the header and compare the old one
        samtools view -H "$local_bam" > "$orig_header"
        sed "$sed_cmd" "$orig_header" > "$temp_header"

        if cmp -s "$orig_header" "$temp_header"; then
            echo "Notice: File is already in '$mode' format. No changes needed."
            echo "Skipping BAM creation."
        else
            echo "Header before:"
            grep "^@SQ" "$orig_header" | head -3 || true

           echo "Header after:"
            grep "^@SQ" "$temp_header" | head -3 || true

            # Reheader into the new BAM
            samtools reheader "$temp_header" "$local_bam" > "$output_bam"

            echo "Indexing..."
            samtools index "$output_bam"

            echo "Verifying chr prefix in new BAM:"
            samtools view -H "$output_bam" | grep "^@SQ" | head -5 || true

            echo "Uploading outputs..."
            bam_dxid=$(dx upload "$output_bam" --project ${DX_PROJECT_CONTEXT_ID} --brief)
            dx-jobutil-add-output output_files "$bam_dxid" --array

            bai_dxid=$(dx upload "$output_bai" --project ${DX_PROJECT_CONTEXT_ID} --brief)
            dx-jobutil-add-output output_indices "$bai_dxid" --array
        fi

        # Clean up the temporary header file
        rm -f "$orig_header" "$temp_header" "$output_bam" "$output_bai"
        echo "Done: $base_name"
    done

    echo "Success: eggd_chr_prefix job completed."
}

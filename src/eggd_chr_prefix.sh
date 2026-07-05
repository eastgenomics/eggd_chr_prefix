#!/bin/bash
# eggd_app

# Exit at any point if there is any error and output each line as it is executed (for debugging)
# -e = exit on error; -x = output each line that is executed to log; -o pipefail = throw an error if there's an error in pipeline
set -e -x -o pipefail

main() {
    dx-download-all-inputs --parallel

    local mode="${mode:-add_chr}" # Defaults to add_chr if no mode is specified
    echo "Starting eggd_chr_prefix execution..."
    echo "Selected Mode: '$mode'"
    mkdir -p inputs outputs

    # Single-file mode (eggd_atlas_cnv workflow stage 0): one BAM in -> one BAM + index out,
    # with PASSTHROUGH when the header is already in the target format (never emit nothing).
    if [ -n "${input_bam:-}" ]; then
        local sf_bam sf_base sf_out sf_sed
        sf_bam="/home/dnanexus/in/input_bam/$(dx describe "$input_bam" --name)"
        sf_base="$(basename "$sf_bam")"
        sf_out="outputs/${sf_base}"
        case "$mode" in
            "add_chr")    sf_sed='s/\tSN:\([0-9][0-9]*\)\t/\tSN:chr\1\t/g; s/\tSN:X\t/\tSN:chrX\t/g; s/\tSN:Y\t/\tSN:chrY\t/g; s/\tSN:MT\t/\tSN:chrM\t/g' ;;
            "remove_chr") sf_sed='s/\tSN:chr\([0-9][0-9]*\)\t/\tSN:\1\t/g; s/\tSN:chrX\t/\tSN:X\t/g; s/\tSN:chrY\t/\tSN:Y\t/g; s/\tSN:chrM\t/\tSN:MT\t/g' ;;
            *) echo "Error: invalid mode '$mode'"; exit 1 ;;
        esac
        samtools view -H "$sf_bam" > inputs/sf_orig.sam
        sed "$sf_sed" inputs/sf_orig.sam > inputs/sf_new.sam
        if cmp -s inputs/sf_orig.sam inputs/sf_new.sam; then
            echo "Single-file mode: already in '$mode' format - passthrough."
            cp "$sf_bam" "$sf_out"
        else
            echo "Single-file mode: reheadering to '$mode'."
            samtools reheader inputs/sf_new.sam "$sf_bam" > "$sf_out"
        fi
        samtools index "$sf_out" "${sf_out}.bai"
        dx-jobutil-add-output output_bam "$(dx upload "$sf_out" --brief)" --class=file
        dx-jobutil-add-output output_bai "$(dx upload "${sf_out}.bai" --brief)" --class=file
        echo "Success: eggd_chr_prefix single-file mode completed."
        return 0
    fi

    # 1. Gather Inputs  
    local bam_files=()

    if [ -n "$input_file" ]; then
        local_bam="/home/dnanexus/in/input_file/$(dx describe "$input_file" --name)"
        bam_files+=("$local_bam")
    fi

    if [ -n "${input_file_array:-}" ]; then
        for i in "${!input_file_array[@]}"; do
            file_id="${input_file_array[$i]}"
            bam_name="$(dx describe "$file_id" --name)"
            local_bam="/home/dnanexus/in/input_file_array/${i}/${bam_name}"
            bam_files+=("$local_bam")
        done
    fi

    if [ ${#bam_files[@]} -eq 0 ] || [ "${bam_files[0]}" == "*.bam" ]; then
    echo "Error: No target BAM files found."
    exit 1
    fi

    echo "Total files selected: ${#bam_files[@]}"


    # 2. Main Execution

    for local_bam in "${bam_files[@]}"; do
    # Extract folder path and base filename
        local base_name="$(basename "$local_bam" .bam)"
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

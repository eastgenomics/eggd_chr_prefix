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
    mkdir -p inputs outputs

    # 1. Gather Inputs

    # Single-file mode (eggd_atlas_cnv workflow stage 0): one BAM in -> one BAM + index out,
    # with PASSTHROUGH when the header is already in the target format (never emit nothing).

    local bam_files=()

    if [ -n "${input_bam:-}" ]; then
        local_bam="/home/dnanexus/in/input_bam/$(dx describe "$input_bam" --name)"
        single_mode=true
        bam_files+=("$local_bam")
    fi

    if [ -n "${input_bam_array:-}" ]; then
        for i in "${!input_bam_array[@]}"; do
            file_id="${input_bam_array[$i]}"
            bam_name="$(dx describe "$file_id" --name)"
            local_bam="/home/dnanexus/in/input_bam_array/${i}/${bam_name}"
            bam_files+=("$local_bam")
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
    local output_bam_paths=()
    local output_bai_paths=()
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
        samtools index "$output_bam"

        echo "Verifying chr prefix in new BAM:"
        samtools view -H "$output_bam" | grep "^@SQ" | head -5 || true
        output_bam_paths+=("$output_bam")
        output_bai_paths+=("$output_bai")
        # Clean up the temporary header file
        rm -f "$orig_header" "$temp_header"
        echo "Done: $base_name"
    done


    echo "Uploading outputs..."
    if [ "$single_mode" = true ]; then
        # single-file mode: upload the single BAM and its index
        local bam_dxid bai_dxid
        bam_dxid="$(dx upload "${output_bam_paths[0]}" --project "${DX_PROJECT_CONTEXT_ID}" --brief)"
        bai_dxid="$(dx upload "${output_bai_paths[0]}" --project "${DX_PROJECT_CONTEXT_ID}" --brief)"
        dx-jobutil-add-output output_bam "$bam_dxid" --class=file
        dx-jobutil-add-output output_bai "$bai_dxid" --class=file
        echo "Success: single-file mode completed."
    else
        # array mode: upload all BAMs and their indices
        local uploaded_bams=()
        local uploaded_bais=()
        local f
       # Upload BAMs and BAIs in parallel and capture their DX IDs
        mapfile -t uploaded_bams < <(dx upload "${output_bam_paths[@]}" --project "${DX_PROJECT_CONTEXT_ID}" --brief)
        mapfile -t uploaded_bais < <(dx upload "${output_bai_paths[@]}" --project "${DX_PROJECT_CONTEXT_ID}" --brief)
        for f in "${uploaded_bams[@]}"; do
            dx-jobutil-add-output output_files "$f" --array
        done
        for f in "${uploaded_bais[@]}"; do
            dx-jobutil-add-output output_indices "$f" --array
        done
        echo "Success: array mode completed."
    fi
    echo "Success: eggd_chr_prefix job completed."
}

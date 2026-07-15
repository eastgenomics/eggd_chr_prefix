# Changelog

## 1.1.0
Added a **single-file mode** for use as stage 0 of the `eggd_atlas_cnv` somatic CNV workflow,
alongside the existing array interface (backward compatible):
- New optional input `input_bam` (single BAM) and single-file outputs `output_bam` + `output_bai`.
- **Passthrough**: when the header is already in the target format the input BAM is emitted
  unchanged (with a generated index) rather than skipped — so downstream workflow stages are never
  starved. The array modes retain their original skip-when-already-formatted behaviour.
- `mode` still selects `add_chr` (default) / `remove_chr`; the transform is unchanged.

## 1.0.0
Initial release — array in/out (`input_file`/`input_file_array` -> `output_files`/`output_indices`),
`add_chr` / `remove_chr` reheader modes.

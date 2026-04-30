process MULTIQC {
    tag "all_samples"
    publishDir "${params.outdir}/multiqc", mode: 'copy'
    errorStrategy 'ignore'   // MultiQC başarısız olsa bile pipeline devam eder

    input:
    path(qc_files, stageAs: "inputs/?/*")

    output:
    path("multiqc_report.html"), optional: true, emit: report
    path("multiqc_data/"),       optional: true, emit: data

    script:
    """
    multiqc \\
        --title "Phage Pipeline QC Report" \\
        --force \\
        --outdir . \\
        . || echo "[UYARI] MultiQC başarısız — diğer adımlar etkilenmez."
    """
}

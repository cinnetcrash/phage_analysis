process MULTIQC {
    tag "all_samples"
    publishDir "${params.outdir}/multiqc", mode: 'copy'

    input:
    path(qc_files)

    output:
    path("multiqc_report.html"), emit: report
    path("multiqc_data/"),       emit: data

    script:
    """
    multiqc \\
        --title "Phage Pipeline QC Report" \\
        --force \\
        --outdir . \\
        .
    """
}

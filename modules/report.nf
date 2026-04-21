process SUMMARY_REPORT {
    tag "all_samples"
    publishDir "${params.outdir}", mode: 'copy'

    input:
    val(results_dir)

    output:
    path("phage_pipeline_report.html"), emit: report

    script:
    """
    python3 ${projectDir}/bin/generate_report.py \\
        --results-dir ${results_dir} \\
        --output phage_pipeline_report.html \\
        --pipeline-version ${workflow.manifest.version ?: '1.0'}
    """
}

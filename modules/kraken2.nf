process KRAKEN2 {
    tag "${meta.id}"
    publishDir "${params.outdir}/kraken2/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(r1), path(r2)

    output:
    tuple val(meta), path("${meta.id}_kraken2_report.txt"), emit: report
    tuple val(meta), path("${meta.id}_kraken2_output.txt"), emit: output

    script:
    """
    kraken2 \\
        --db ${params.kraken2_db} \\
        --paired ${r1} ${r2} \\
        --threads ${task.cpus} \\
        --memory-mapping \\
        --use-names \\
        --report ${meta.id}_kraken2_report.txt \\
        --output ${meta.id}_kraken2_output.txt
    """
}

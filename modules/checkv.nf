process CHECKV {
    tag "${meta.id}"
    publishDir "${params.outdir}/checkv/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(viral_fasta)

    output:
    tuple val(meta), path("viruses.fna"),              emit: viruses
    tuple val(meta), path("proviruses.fna"),            emit: proviruses
    tuple val(meta), path("quality_summary.tsv"),       emit: summary
    tuple val(meta), path("completeness.tsv"),          emit: completeness
    tuple val(meta), path("contamination.tsv"),         emit: contamination
    path "checkv_results/",                             emit: all

    script:
    """
    checkv end_to_end \\
        ${viral_fasta} \\
        checkv_results \\
        -t ${task.cpus} \\
        -d ${params.checkv_db}

    # Çıktıları ana dizine kopyala (publishDir için)
    cp checkv_results/viruses.fna       ./viruses.fna
    cp checkv_results/proviruses.fna    ./proviruses.fna
    cp checkv_results/quality_summary.tsv ./quality_summary.tsv
    cp checkv_results/completeness.tsv    ./completeness.tsv
    cp checkv_results/contamination.tsv   ./contamination.tsv
    """
}

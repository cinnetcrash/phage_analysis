process BACPHLIP {
    tag "${meta.id}"
    publishDir "${params.outdir}/bacphlip/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("${meta.id}_bacphlip.tsv"), emit: predictions

    script:
    """
    bacphlip \\
        -i ${fasta} \\
        --multi_fasta \\
        -f
    mv ${fasta}.bacphlip ${meta.id}_bacphlip.tsv
    """
}

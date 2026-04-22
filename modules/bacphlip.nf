process BACPHLIP {
    tag "${meta.id}"
    publishDir "${params.outdir}/bacphlip/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("${meta.id}_bacphlip.tsv"), emit: predictions

    script:
    """
    NSEQ=\$(grep -c '^>' ${fasta})
    if [ "\$NSEQ" -gt 1 ]; then
        bacphlip -i ${fasta} --multi_fasta -f
    else
        bacphlip -i ${fasta} -f
    fi
    mv ${fasta}.bacphlip ${meta.id}_bacphlip.tsv
    """
}

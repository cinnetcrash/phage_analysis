/*
  vHULK – makine öğrenmesi tabanlı faj-konak tahmini
*/
process VHULK {
    tag "${meta.id}"
    publishDir "${params.outdir}/vhulk/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("${meta.id}_vhulk_predictions.tsv"), emit: predictions

    script:
    """
    # vHULK -i dizin bekliyor; .fa/.fasta uzantısı gerekli
    mkdir -p vhulk_input
    cp ${fasta} vhulk_input/${meta.id}.fasta

    python3 /home/analysis/vHULK/vHULK.py \\
        -i vhulk_input \\
        -o vhulk_out \\
        -t ${task.cpus}

    cp vhulk_out/predictions/${meta.id}.csv ${meta.id}_vhulk_predictions.tsv
    """
}

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
    # vHULK: giriş FASTA → output klasörü
    python3 \$(which vHULK.py) \\
        -i ${fasta} \\
        -o vhulk_out \\
        -t ${task.cpus}

    # Tahmin dosyasını yeniden adlandır
    cp vhulk_out/output.csv ${meta.id}_vhulk_predictions.tsv 2>/dev/null || \\
    cp vhulk_out/*.tsv     ${meta.id}_vhulk_predictions.tsv
    """
}

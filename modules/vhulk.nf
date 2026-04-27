/*
  vHULK — machine-learning based phage host prediction
*/
process VHULK {
    tag "${meta.id}"
    publishDir "${params.outdir}/vhulk/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("${meta.id}_vhulk_predictions.tsv"), emit: predictions

    script:
    def db_arg = params.vhulk_db ? "-d ${params.vhulk_db}" : ""
    """
    mkdir -p vhulk_input
    cp ${fasta} vhulk_input/${meta.id}.fasta

    vHULK.py \\
        -i vhulk_input \\
        -o vhulk_out \\
        ${db_arg} \\
        -t ${task.cpus}

    cp vhulk_out/predictions/${meta.id}.csv ${meta.id}_vhulk_predictions.tsv
    """
}

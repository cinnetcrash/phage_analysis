/*
  Phrokka – faj odaklı anotasyon (E. coli örnekleri için kullanılır)
*/
process PHROKKA {
    tag "${meta.id}"
    publishDir "${params.outdir}/phrokka/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("${meta.id}.gbk"),  emit: gbk
    tuple val(meta), path("${meta.id}.gff"),  emit: gff
    tuple val(meta), path("${meta.id}.faa"),  emit: faa   // protein FASTA (vContact2 için)
    tuple val(meta), path("${meta.id}_cds_final_merged_output.tsv"), optional: true, emit: tsv

    script:
    def db_arg = params.pharokka_db ? "-d ${params.pharokka_db}" : ""
    """
    pharokka.py \\
        -i ${fasta} \\
        -o phrokka_out \\
        ${db_arg} \\
        -p ${meta.id} \\
        -t ${task.cpus} \\
        --force

    cp phrokka_out/${meta.id}.gbk .
    cp phrokka_out/${meta.id}.gff .
    cp phrokka_out/${meta.id}.faa . 2>/dev/null || cp phrokka_out/phanotate.faa ${meta.id}.faa
    cp phrokka_out/${meta.id}_cds_final_merged_output.tsv . 2>/dev/null || true
    """
}

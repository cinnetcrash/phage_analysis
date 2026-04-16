process VIRSORTER2 {
    tag "${meta.id}"
    publishDir "${params.outdir}/virsorter2/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(contigs)

    output:
    tuple val(meta), path("final-viral-combined.fa"),    emit: viral_seqs
    tuple val(meta), path("final-viral-score.tsv"),      emit: scores
    tuple val(meta), path("final-viral-boundary.tsv"),   emit: boundaries

    script:
    """
    virsorter run \\
        -i ${contigs} \\
        -w . \\
        --db-dir ${params.virsorter2_db} \\
        --min-length ${params.min_contig_len} \\
        --include-groups dsDNAphage,NCLDV,RNA,ssDNA,lavidaviridae \\
        -j ${task.cpus} \\
        all
    """
}

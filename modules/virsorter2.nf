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
    // Boş contig dosyasını kontrol et
    """
    if [ ! -s "${contigs}" ]; then
        echo "[UYARI] Boş contig dosyası: ${meta.id} — VirSorter2 atlanıyor."
        touch final-viral-combined.fa
        printf "seqname\\tmax_score\\tmax_score_group\\tlength\\thallmark\\tviral\\tcellular\\n" > final-viral-score.tsv
        printf "seqname\\ttrim_start\\ttrim_end\\tprotein_start\\tprotein_end\\tcat\\n"         > final-viral-boundary.tsv
        exit 0
    fi

    virsorter run \\
        -i ${contigs} \\
        -w . \\
        --db-dir ${params.virsorter2_db} \\
        --min-length ${params.min_contig_len} \\
        --include-groups dsDNAphage,NCLDV,RNA,ssDNA,lavidaviridae \\
        --use-conda-off \\
        -j ${task.cpus} \\
        all
    """
}

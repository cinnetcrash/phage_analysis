/*
  Prokka – viral gen anotasyonu
  Listeria, Salmonella, Enterococcus, Staphylococcus örnekleri için
*/
process PROKKA {
    tag "${meta.id}"
    publishDir "${params.outdir}/prokka/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("${meta.id}.gbk"), emit: gbk
    tuple val(meta), path("${meta.id}.gff"), emit: gff
    tuple val(meta), path("${meta.id}.faa"), emit: faa   // protein FASTA (vContact2 için)
    tuple val(meta), path("${meta.id}.fna"), emit: fna
    tuple val(meta), path("${meta.id}.tsv"), emit: tsv

    script:
    // locustag: sadece harf, max 4 karakter, büyük harf
    def locustag = meta.id.replaceAll(/[^A-Za-z]/, '').take(4).toUpperCase() ?: 'PHAG'
    """
    # Contig ID'leri kısalt (Prokka ≤37 karakter gerektirir)
    awk '/^>/{n++; print ">contig_"n; next}{print}' ${fasta} > renamed.fna

    prokka \\
        --outdir prokka_out \\
        --prefix ${meta.id} \\
        --kingdom Viruses \\
        --locustag ${locustag} \\
        --centre X --compliant \\
        --force \\
        --cpus ${task.cpus} \\
        renamed.fna

    cp prokka_out/${meta.id}.gbk .
    cp prokka_out/${meta.id}.gff .
    cp prokka_out/${meta.id}.faa .
    cp prokka_out/${meta.id}.fna .
    cp prokka_out/${meta.id}.tsv .
    """
}

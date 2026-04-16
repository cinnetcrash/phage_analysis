/*
  BLAST – nükleotid kimlik doğrulama ve yakın akraba arama
*/
process BLAST {
    tag "${meta.id}"
    publishDir "${params.outdir}/blast/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("${meta.id}_blast_results.tsv"), emit: results

    script:
    """
    blastn \\
        -query ${fasta} \\
        -db ${params.blast_db} \\
        -out ${meta.id}_blast_results.tsv \\
        -outfmt "6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore stitle staxids" \\
        -evalue 1e-5 \\
        -max_target_seqs 10 \\
        -num_threads ${task.cpus}
    """
}

/*
  vContact2 – viral protein benzerliğine dayalı taksonomi kümeleme
  Tüm örneklerin .faa dosyaları birleştirilerek tek seferde çalıştırılır
*/
process VCONTACT2 {
    tag "all_samples"
    publishDir "${params.outdir}/vcontact2", mode: 'copy'

    input:
    path(faa_files)   // list of *.faa dosyaları

    output:
    path("output/"),              emit: results
    path("all_proteins.faa"),     emit: merged_faa
    path("gene_to_genome.csv"),   emit: gene_map

    script:
    """
    # 1) Tüm protein FASTA'larını birleştir
    cat ${faa_files} > all_proteins.faa

    # 2) gene-to-genome CSV'si üret
    python3 ${projectDir}/bin/make_gene2genome.py \\
        --faa all_proteins.faa \\
        --output gene_to_genome.csv

    # 3) vContact2 çalıştır
    vcontact2 \\
        --raw-proteins all_proteins.faa \\
        --rel-mode Diamond \\
        --proteins-fp gene_to_genome.csv \\
        --db ${params.vcontact2_db} \\
        --pcs-mode MCL \\
        --vcs-mode ClusterONE \\
        --output-dir output \\
        --threads ${task.cpus}
    """
}

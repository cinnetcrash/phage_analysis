process CHECKV {
    tag "${meta.id}"
    publishDir "${params.outdir}/checkv/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(viral_fasta)

    output:
    tuple val(meta), path("viruses.fna"),              emit: viruses
    tuple val(meta), path("proviruses.fna"),            emit: proviruses
    tuple val(meta), path("quality_summary.tsv"),       emit: summary
    tuple val(meta), path("completeness.tsv"),          emit: completeness
    tuple val(meta), path("contamination.tsv"),         emit: contamination
    path "checkv_results/",                             emit: all

    script:
    """
    # Boş FASTA kontrolü — contig üretilememiş örnekleri nazikçe atla
    if [ ! -s "${viral_fasta}" ]; then
        echo "[UYARI] Giriş FASTA boş: ${meta.id} — CheckV atlanıyor."
        mkdir -p checkv_results
        touch viruses.fna proviruses.fna
        printf "contig_id\\tcheckv_quality\\tcompleteness\\twarnings\\n" > quality_summary.tsv
        printf "contig_id\\tcompleteness_method\\tcompleteness\\n"        > completeness.tsv
        printf "contig_id\\tcontamination\\n"                             > contamination.tsv
        exit 0
    fi

    checkv end_to_end \\
        ${viral_fasta} \\
        checkv_results \\
        -t ${task.cpus} \\
        -d ${params.checkv_db}

    # Çıktıları ana dizine kopyala (publishDir için)
    cp checkv_results/viruses.fna         ./viruses.fna
    cp checkv_results/proviruses.fna      ./proviruses.fna
    cp checkv_results/quality_summary.tsv ./quality_summary.tsv
    cp checkv_results/completeness.tsv    ./completeness.tsv
    cp checkv_results/contamination.tsv   ./contamination.tsv
    """
}

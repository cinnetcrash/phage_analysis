/*
  FILTER_CHECKV_CIRCULAR
  ─────────────────────
  CheckV çıktılarından yalnızca circular/complete faj genomlarını seçer.

  Kriter:
    • checkv_quality == "Complete"
    • VEYA completeness >= params.min_completeness (varsayılan %90)
          VE warnings sütununda "DTR" veya "ITR" geçiyor (circular marker)

  Çıktı:
    • filtered_circular.fna  – sadece seçilen genomların FASTA'sı
    • filtered_circular.tsv  – sadece seçilen satırların metadata tablosu
*/
process FILTER_CHECKV_CIRCULAR {
    tag "${meta.id}"
    publishDir "${params.outdir}/checkv_filtered/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(viruses),
                     path(proviruses),
                     path(quality_summary)

    output:
    tuple val(meta), path("filtered_circular.fna"), emit: circular_fasta
    tuple val(meta), path("filtered_circular.tsv"), emit: circular_tsv

    script:
    def min_comp = params.min_completeness ?: 90
    """
    python3 ${projectDir}/bin/filter_checkv_circular.py \\
        --summary      ${quality_summary} \\
        --viruses      ${viruses} \\
        --proviruses   ${proviruses} \\
        --out-fasta    filtered_circular.fna \\
        --out-tsv      filtered_circular.tsv \\
        --min-completeness ${min_comp}
    """
}

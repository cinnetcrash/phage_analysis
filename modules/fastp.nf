process FASTP {
    tag "${meta.id}"
    publishDir "${params.outdir}/fastp/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(r1), path(r2)

    output:
    tuple val(meta), path("${meta.id}_R1_trimmed.fastq.gz"), path("${meta.id}_R2_trimmed.fastq.gz"), emit: reads
    tuple val(meta), path("${meta.id}_fastp.json"), emit: json
    tuple val(meta), path("${meta.id}_fastp.html"), emit: html

    script:
    """
    fastp \\
        -i ${r1} \\
        -I ${r2} \\
        -o ${meta.id}_R1_trimmed.fastq.gz \\
        -O ${meta.id}_R2_trimmed.fastq.gz \\
        -j ${meta.id}_fastp.json \\
        -h ${meta.id}_fastp.html \\
        --thread ${task.cpus} \\
        --detect_adapter_for_pe \\
        --qualified_quality_phred 20 \\
        --length_required 50
    """
}

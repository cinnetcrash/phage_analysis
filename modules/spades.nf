process SPADES {
    tag "${meta.id}"
    publishDir "${params.outdir}/assembly/${meta.id}", mode: 'copy'

    input:
    tuple val(meta), path(r1), path(r2)

    output:
    tuple val(meta), path("contigs.fasta"),                   emit: contigs
    tuple val(meta), path("assembly_graph_after_simplification.gfa"), optional: true, emit: gfa
    path "spades.log",                                        emit: log

    script:
    // --metaviral: SPAdes >= 3.15; eski sürümler için --meta kullan
    def spades_mode = params.spades_mode ?: 'auto'
    """
    # SPAdes versiyon tespiti
    SPADES_VER=\$(spades.py --version 2>&1 | grep -oP '\\d+\\.\\d+' | head -1)
    MAJOR=\$(echo \$SPADES_VER | cut -d. -f1)
    MINOR=\$(echo \$SPADES_VER | cut -d. -f2)

    if [ "${spades_mode}" = "auto" ]; then
        # 3.15+ → --metaviral; altı → --meta
        if [ "\$MAJOR" -gt 3 ] || ( [ "\$MAJOR" -eq 3 ] && [ "\$MINOR" -ge 15 ] ); then
            MODE="--metaviral"
        else
            MODE="--meta"
        fi
    else
        MODE="--${spades_mode}"
    fi

    spades.py \\
        \$MODE \\
        -1 ${r1} \\
        -2 ${r2} \\
        -o . \\
        -t ${task.cpus} \\
        -m ${task.memory.toGiga()} || true

    # metaviralSPAdes kontig bulamazsa contigs.fasta oluşturmaz; boş dosya yarat
    [ -f contigs.fasta ] || touch contigs.fasta

    # Kısa contigleri filtrele (>= min_contig_len)
    awk -v min=${params.min_contig_len} '
        /^>/ { if (header != "" && length(seq) >= min) printf "%s\\n%s\\n", header, seq
               header = \$0; seq = ""; next }
               { seq = seq \$0 }
        END   { if (header != "" && length(seq) >= min) printf "%s\\n%s\\n", header, seq }
    ' contigs.fasta > contigs_filtered.fasta
    mv contigs_filtered.fasta contigs.fasta
    """
}

#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

/*
========================================================================================
    phage_analysis
    https://github.com/cinnetcrash/phage_analysis
========================================================================================
    Bacteriophage discovery and characterization pipeline

    Steps:
      1.  FastQC          — raw read quality control
      2.  Kraken2         — viral taxonomic classification
      3.  SPAdes          — metaviral assembly (--metaviral)
      4.  VirSorter2      — viral sequence identification
      5.  CheckV          — genome completeness & quality
      6.  [Filter]        — keep only CIRCULAR / COMPLETE genomes
      7.  BACPHLIP        — lytic vs. lysogenic prediction
      8.  Phrokka/Prokka  — phage genome annotation
      9.  vContact2       — viral taxonomy clustering
      10. vHULK           — host prediction
      11. BLAST           — nucleotide identity (optional)
      12. MultiQC         — aggregated QC report

    Usage:
      nextflow run cinnetcrash/phage_analysis \\
          -profile conda \\
          --samplesheet samplesheet.csv \\
          --kraken2_db  /path/to/kraken2_db \\
          --virsorter2_db /path/to/virsorter2_db \\
          --checkv_db   /path/to/checkv_db \\
          --outdir      results
========================================================================================
*/

include { FASTQC                  } from './modules/fastqc'
include { KRAKEN2                 } from './modules/kraken2'
include { SPADES                  } from './modules/spades'
include { VIRSORTER2              } from './modules/virsorter2'
include { CHECKV                  } from './modules/checkv'
include { FILTER_CHECKV_CIRCULAR  } from './modules/filter_checkv'
include { BACPHLIP                } from './modules/bacphlip'
include { PHROKKA                 } from './modules/phrokka'
include { PROKKA                  } from './modules/prokka'
include { VCONTACT2               } from './modules/vcontact2'
include { VHULK                   } from './modules/vhulk'
include { BLAST                   } from './modules/blast'
include { MULTIQC                 } from './modules/multiqc'

// ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────

def help_message() {
    log.info """
    ╔══════════════════════════════════════════════════════════════════╗
    ║              phage_analysis  v${workflow.manifest.version}                      ║
    ║     Bacteriophage Discovery & Characterization Pipeline          ║
    ╚══════════════════════════════════════════════════════════════════╝

    Usage:
      nextflow run cinnetcrash/phage_analysis [options]

    Required:
      --samplesheet     Path to CSV file (sample_id,host,R1,R2)
      --kraken2_db      Path to Kraken2 database
      --virsorter2_db   Path to VirSorter2 database
      --checkv_db       Path to CheckV database

    Optional:
      --blast_db           Path to BLAST database (skip BLAST if not set)
      --vcontact2_db       vContact2 DB name (default: ProkaryoticViralRefSeq94-Merged)
      --outdir             Output directory (default: results)
      --min_contig_len     Minimum contig length in bp (default: 1000)
      --min_completeness   CheckV completeness threshold % (default: 90)
      --skip_virsorter     Skip VirSorter2, pass SPAdes contigs directly to CheckV
      --skip_kraken2       Skip Kraken2 classification step
      --max_cpus           Max CPUs per job (default: 32)
      --max_memory         Max memory per job (default: 128.GB)
      --max_time           Max walltime per job (default: 72.h)

    Profiles:
      -profile conda        Use conda environments (recommended)
      -profile docker       Use Docker containers
      -profile singularity  Use Singularity containers
      -profile slurm        Submit to SLURM scheduler
      -profile test         Run with bundled test data

    Samplesheet format (CSV with header):
      sample_id,host,R1,R2
      ECO111_S1,ecoli,/data/ECO111_S1_R1_001.fastq,/data/ECO111_S1_R2_001.fastq

    Valid host values: ecoli | listeria | salmonella | enterococcus | staphylococcus

    More info: https://github.com/cinnetcrash/phage_analysis
    """.stripIndent()
}

def validate_params() {
    if (params.help) {
        help_message()
        System.exit(0)
    }
    if (!params.samplesheet) {
        log.error "ERROR: --samplesheet is required. See --help for usage."
        System.exit(1)
    }
    if (!params.skip_kraken2 && !params.kraken2_db) {
        log.error "ERROR: --kraken2_db is required (or use --skip_kraken2). See --help for usage."
        System.exit(1)
    }
    if (!params.skip_virsorter && !params.virsorter2_db) {
        log.error "ERROR: --virsorter2_db is required (or use --skip_virsorter). See --help for usage."
        System.exit(1)
    }
    if (!params.checkv_db) {
        log.error "ERROR: --checkv_db is required. See --help for usage."
        System.exit(1)
    }
}

def parse_samplesheet(csv_file) {
    Channel
        .fromPath(csv_file)
        .splitCsv(header: true, strip: true)
        .map { row ->
            def valid_hosts = ['ecoli', 'listeria', 'salmonella', 'enterococcus', 'staphylococcus']
            def host = row.host?.toLowerCase()?.trim()
            if (!valid_hosts.contains(host)) {
                log.warn "Unknown host '${row.host}' for sample '${row.sample_id}'. " +
                         "Valid: ${valid_hosts.join(', ')}. Defaulting to generic annotation."
                host = 'other'
            }
            def meta = [ id: row.sample_id, host: host ]
            [ meta, file(row.R1, checkIfExists: true), file(row.R2, checkIfExists: true) ]
        }
}

// ── Ana workflow ──────────────────────────────────────────────────────────────

workflow {

    validate_params()

    log.info """
    ╔══════════════════════════════════════════════════════════════════╗
    ║              phage_analysis  v${workflow.manifest.version}
    ╠══════════════════════════════════════════════════════════════════╣
    ║  Samplesheet   : ${params.samplesheet}
    ║  Output dir    : ${params.outdir}
    ║  Kraken2 DB    : ${params.skip_kraken2 ? '(skipped)' : params.kraken2_db}
    ║  VirSorter2 DB : ${params.skip_virsorter ? '(skipped)' : params.virsorter2_db}
    ║  CheckV DB     : ${params.checkv_db}
    ║  BLAST DB      : ${params.blast_db ?: '(skipped)'}
    ║  Min contig    : ${params.min_contig_len} bp
    ║  Min complete  : ${params.min_completeness}%
    ╚══════════════════════════════════════════════════════════════════╝
    """.stripIndent()

    // ── 0. Girdi ──────────────────────────────────────────────────────────────
    reads_ch = parse_samplesheet(params.samplesheet)

    // ── 1. FastQC ─────────────────────────────────────────────────────────────
    FASTQC(reads_ch)

    // ── 2. Kraken2 – viral sınıflandırma (opsiyonel) ─────────────────────────
    if (!params.skip_kraken2) {
        KRAKEN2(reads_ch)
    }

    // ── 3. SPAdes metaviral assembly ──────────────────────────────────────────
    SPADES(reads_ch)

    // ── 4. VirSorter2 – viral sekans tespiti (opsiyonel) ──────────────────────
    // --skip_virsorter: SPAdes contigleri doğrudan CheckV'ye gönderilir
    if (!params.skip_virsorter) {
        VIRSORTER2(SPADES.out.contigs)
        checkv_input_ch = VIRSORTER2.out.viral_seqs
    } else {
        log.warn "VirSorter2 atlandı — SPAdes contigleri doğrudan CheckV'ye gönderiliyor."
        checkv_input_ch = SPADES.out.contigs
    }

    // ── 5. CheckV – kalite değerlendirme ─────────────────────────────────────
    CHECKV(checkv_input_ch)

    // ── 6. Circular / Complete filtre ────────────────────────────────────────
    checkv_for_filter = CHECKV.out.viruses
        .join(CHECKV.out.proviruses, by: 0)
        .join(CHECKV.out.summary,   by: 0)
        .map { meta, vir, pro, summ -> tuple(meta, vir, pro, summ) }

    FILTER_CHECKV_CIRCULAR(checkv_for_filter)

    // Hiç circular genom çıkmayan örnekleri düşür
    circular_ch = FILTER_CHECKV_CIRCULAR.out.circular_fasta
        .filter { meta, fasta -> fasta.size() > 0 }

    // ──────────────────────────────────────────────────────────────────────────
    //  AŞAĞIDA SADECE CIRCULAR / COMPLETE FAJLAR İŞLENİR
    // ──────────────────────────────────────────────────────────────────────────

    // ── 7. BACPHLIP – yaşam döngüsü tahmini ──────────────────────────────────
    BACPHLIP(circular_ch)

    // ── 8. Anotasyon ──────────────────────────────────────────────────────────
    phrokka_input = circular_ch.filter { meta, _f -> meta.host == 'ecoli' }
    prokka_input  = circular_ch.filter { meta, _f -> meta.host != 'ecoli' }

    PHROKKA(phrokka_input)
    PROKKA(prokka_input)

    // tüm .faa → vContact2 için birleştir
    all_faa_ch = PHROKKA.out.faa
        .mix(PROKKA.out.faa)
        .map { meta, faa -> faa }
        .collect()

    // ── 9. vContact2 – viral taksonomi kümeleme ───────────────────────────────
    VCONTACT2(all_faa_ch)

    // ── 10. vHULK – konak tahmini ─────────────────────────────────────────────
    VHULK(circular_ch)

    // ── 11. BLAST – opsiyonel ─────────────────────────────────────────────────
    if (params.blast_db) {
        BLAST(circular_ch)
    }

    // ── 12. MultiQC raporu ────────────────────────────────────────────────────
    qc_files = FASTQC.out.zip
        .map { meta, zips -> zips }
        .mix(CHECKV.out.summary.map { meta, s -> s })

    if (!params.skip_kraken2) {
        qc_files = qc_files.mix(KRAKEN2.out.report.map { meta, r -> r })
    }

    MULTIQC(qc_files.collect())
}

workflow.onComplete {
    def status = workflow.success ? 'SUCCESS' : 'FAILED'
    log.info """
    ╔══════════════════════════════════════════════════╗
    ║  phage_analysis  —  ${status}
    ║  Duration : ${workflow.duration}
    ║  Output   : ${params.outdir}
    ║  Error    : ${workflow.errorMessage ?: 'none'}
    ╚══════════════════════════════════════════════════╝
    """.stripIndent()
}

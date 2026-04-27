# phage_analysis

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A523.04.0-23aa62.svg)](https://www.nextflow.io/)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg)](https://sylabs.io/docs/)

A Nextflow DSL2 pipeline for **bacteriophage discovery and characterization** from paired-end Illumina reads.

Supported bacterial hosts: *E. coli*, *Listeria monocytogenes*, *Salmonella* spp., *Enterococcus* spp., *Staphylococcus* spp.

---

## Pipeline overview

```
Paired-end FASTQ
       │
       ├──► FastQC           (raw read QC)
       ├──► Kraken2          (viral taxonomic classification)
       │
       └──► SPAdes --metaviral   (viral metagenome assembly)
                   │
                   └──► VirSorter2   (viral sequence detection)
                               │
                               └──► CheckV   (completeness & quality)
                                         │
                              ╔══════════╧═════════════╗
                              ║  FILTER: circular /    ║
                              ║  complete genomes only ║
                              ╚══════════╤═════════════╝
                                         │
                    ┌────────────────────┼──────────────────────┐
                    │                   │                        │
                 BACPHLIP            vHULK                    BLAST*
           (lifestyle pred.)    (host prediction)     (nucleotide identity)
                    │
           ┌────────┴────────┐
        Phrokka           Prokka
      (E. coli only)   (all others)
           └────────┬────────┘
                    │
                vContact2
          (viral taxonomy clustering)
                    
       MultiQC  (aggregated QC report)
```

> `*` BLAST step is **optional** — skipped if `--blast_db` is not provided.

### Circular / complete filter

After CheckV, only genomes passing **both** criteria below are carried forward:

| Criterion | Meaning |
|-----------|---------|
| `checkv_quality == "Complete"` | CheckV certifies a full phage genome |
| `completeness ≥ N%` **and** DTR / ITR detected | High completeness + circular topology marker |

The threshold `N` is configurable via `--min_completeness` (default `90`).

---

## Quick start

### 1. Prerequisites

- **Miniconda** (or Mamba) — [install guide](https://docs.conda.io/en/latest/miniconda.html)
- **~16 GB free disk** for databases (+ ~270 GB if BLAST nt is needed)

> **Nextflow ve Java bu pipeline'ın conda ortamına dahildir** — ayrı kurulum gerekmez.
> Sisteminizde yüklü bir Java varsa uyumsuzluk yaşamamak için ortamdaki Java'yı kullanın:
> ```bash
> export JAVA_HOME=$CONDA_PREFIX
> export JAVA_CMD=$CONDA_PREFIX/bin/java
> ```

### 2. Conda ortamını kur (tek adım)

Pipeline, **tüm araçları tek bir conda ortamında** (`phage_analysis`) çalıştırır.
Nextflow dahil tüm bağımlılıklar bu ortamda bulunur.

```bash
# Repoyu klonla
git clone https://github.com/cinnetcrash/phage_analysis.git
cd phage_analysis

# Conda ortamını oluştur (~2–5 GB disk, ~10–20 dk)
conda env create -f environment.yml

# Ortamı aktifleştir
conda activate phage_analysis

# Nextflow'un ortamdaki Java'yı kullandığından emin ol
export JAVA_HOME=$CONDA_PREFIX
export JAVA_CMD=$CONDA_PREFIX/bin/java

# Kontrol
nextflow -version
```

> **Mamba ile çok daha hızlı kurulum:**
> ```bash
> mamba env create -f environment.yml
> ```

#### Bilinen sürüm notları

| Araç | Not |
|------|-----|
| **bacphlip 0.9.6** | Modelleri scikit-learn 0.23 ile eğitildi; ortamdaki 1.0.x ile `InconsistentVersionWarning` verebilir. Tahminler çalışır. |
| **vHULK** | TensorFlow 2.9 (Python 3.9 uyumlu) ile çalışır; TF 2.8 modelleri geriye dönük uyumludur. |
| **vContact2** | networkx 2.x API'si gerektirir; `networkx>=2.7,<3.0` ile sabitlenmiştir. |
| **VirSorter2** | DB kurulumu için `virsorter setup -d <db_dir> -j <threads>` komutu gerekmektedir. |

### 3. Veritabanlarını kur

```bash
# Tüm veritabanları (~16 GB, ~1–2 saat)
bash bin/setup_databases.sh --db-dir ~/phage_databases --threads 8
```

Komut tamamlandığında, tüm yollar önceden doldurulmuş `nextflow run` komutu ekrana yazdırılır.

**Kurulacaklar:**

| Veritabanı | Boyut | Amaç |
|------------|-------|-------|
| Kraken2 viral | ~8 GB | Taksonomik sınıflandırma |
| VirSorter2 | ~3 GB | Viral sekans tespiti |
| CheckV | ~3 GB | Genom kalitesi değerlendirme |
| Pharokka | ~2 GB | Faj anotasyonu (E. coli fajları) |
| BLAST nt | ~270 GB | Nükleotid kimliği *(opsiyonel — `--install-blast`)* |

**Bazı veritabanları zaten kuruluysa** atla:
```bash
bash bin/setup_databases.sh \
    --db-dir ~/phage_databases \
    --skip-kraken2 \
    --threads 8
```

**Kurulum yapmadan önizle:**
```bash
bash bin/setup_databases.sh --db-dir ~/phage_databases --dry-run
```

### 4. Örnek tablosunu hazırla

Şablonu kopyala ve düzenle:

```bash
cp assets/samplesheet_template.csv my_samples.csv
```

Format (başlık satırlı CSV):

```csv
sample_id,host,R1,R2
ECO111_S1,ecoli,/data/ECO111_S1_R1_001.fastq.gz,/data/ECO111_S1_R2_001.fastq.gz
LM-11_S16,listeria,/data/LM-11_S16_R1_001.fastq,/data/LM-11_S16_R2_001.fastq
```

Geçerli `host` değerleri: `ecoli` · `listeria` · `salmonella` · `enterococcus` · `staphylococcus`

### 5. Çalıştır

```bash
# Tek ortam profili ile (önerilen)
nextflow run cinnetcrash/phage_analysis \
    -profile conda_unified \
    --samplesheet my_samples.csv \
    --kraken2_db  /path/to/kraken2_db \
    --virsorter2_db /path/to/virsorter2_db \
    --checkv_db   /path/to/checkv_db \
    --outdir      results
```

Kesintiden sonra kaldığı yerden devam et:

```bash
nextflow run cinnetcrash/phage_analysis ... -resume
```

---

## Parameters

### Required

| Parameter | Description |
|-----------|-------------|
| `--samplesheet` | Path to CSV samplesheet |
| `--kraken2_db` | Kraken2 database directory |
| `--virsorter2_db` | VirSorter2 database directory |
| `--checkv_db` | CheckV database directory |

### Optional

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--outdir` | `results` | Output directory |
| `--blast_db` | *(none)* | BLAST database path — BLAST skipped if omitted |
| `--vcontact2_db` | `ProkaryoticViralRefSeq94-Merged` | vContact2 reference DB name |
| `--min_contig_len` | `1000` | Minimum contig length (bp) passed to VirSorter2 |
| `--min_completeness` | `90` | CheckV completeness threshold (%) for DTR/ITR genomes |
| `--max_cpus` | `32` | Max CPUs per process |
| `--max_memory` | `128.GB` | Max memory per process |
| `--max_time` | `72.h` | Max wall time per process |

---

## Profiles

| Profil | Açıklama |
|--------|----------|
| `conda_unified` | **Önerilen** — tek `phage_analysis` conda ortamı (`environment.yml`) |
| `conda` | Her adım için ayrı conda ortamları (eski davranış) |
| `docker` | Docker container'ları |
| `singularity` | Singularity container'ları (HPC uyumlu) |
| `slurm` | SLURM zamanlayıcısına iş gönderir |
| `test` | Dahili test verisiyle çalışır |
| `test_local` | Yerel sistem kurulumunu kullanır (`conf/test_local.config`) |

---

## Output structure

```
results/
├── fastqc/             FastQC HTML & ZIP reports per sample
├── kraken2/            Kraken2 classification reports
├── assembly/           SPAdes contigs per sample
├── virsorter2/         VirSorter2 viral sequences & scores
├── checkv/             CheckV quality summaries
├── checkv_filtered/    Circular/complete genomes (post-filter)
├── bacphlip/           Lifestyle predictions (lytic / lysogenic)
├── phrokka/            Phage annotations — E. coli samples
├── prokka/             Phage annotations — all other hosts
├── vcontact2/          Viral taxonomy clustering output
├── vhulk/              Host prediction results
├── blast/              BLAST nucleotide search results
├── multiqc/            Aggregated MultiQC HTML report
└── pipeline_info/      Nextflow timeline, report & trace files
```

---

## Tools & versions

| Tool | Version | Purpose |
|------|---------|---------|
| FastQC | 0.12.1 | Read quality control |
| Kraken2 | 2.1.3 | Taxonomic classification |
| SPAdes | 4.0.0 | Metaviral assembly |
| VirSorter2 | 2.2.4 | Viral sequence identification |
| CheckV | 1.0.1 | Genome completeness assessment |
| BACPHLIP | 0.9.6 | Phage lifestyle prediction |
| Pharokka (Phrokka) | 1.7.3 | Phage genome annotation |
| Prokka | 1.14.6 | Genome annotation |
| vContact2 | 0.9.19 | Viral taxonomy clustering |
| vHULK | 1.0.0 | Host range prediction |
| BLAST+ | 2.15.0 | Nucleotide identity |
| MultiQC | 1.21 | QC aggregation |

---

## Citation

If you use this pipeline, please cite the individual tools listed above. A dedicated citation will be added in a future release.

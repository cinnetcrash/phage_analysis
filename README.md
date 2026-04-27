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
       └──► fastp            (adapter trimming & quality filtering)
                   │
                   └──► SPAdes --metaviral   (viral metagenome assembly)
                               │
                               └──► VirSorter2   (viral sequence detection)
                                           │
                                           └──► CheckV   (completeness & quality)
                                                     │
                                        ╔════════════╧════════════╗
                                        ║  FILTER: circular /     ║
                                        ║  complete genomes only  ║
                                        ╚════════════╤════════════╝
                                                     │
                              ┌──────────────────────┼──────────────────────┐
                              │                      │                       │
                           BACPHLIP               vHULK                  BLAST*
                     (lifestyle pred.)       (host prediction)   (nucleotide identity)
                              │
                     ┌────────┴────────┐
                  Phrokka           Prokka
                (E. coli only)   (all others)
                     └────────┬────────┘
                              │
                          vContact2
                    (viral taxonomy clustering)

       MultiQC  (aggregated QC report)
       Summary report (HTML)
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

- **Miniconda / Mamba** — [install guide](https://docs.conda.io/en/latest/miniconda.html)  
  or **Docker** ≥ 20.10 — [install guide](https://docs.docker.com/get-docker/)
- **~16 GB free disk** for databases (+ ~270 GB if BLAST nt is needed)

> Nextflow and Java 17 are bundled inside the conda environment and Docker image — no separate installation required.

---

### Option A — Conda (single environment)

All pipeline tools run inside a single `phage_analysis` conda environment.

```bash
# 1. Clone the repository
git clone https://github.com/cinnetcrash/phage_analysis.git
cd phage_analysis

# 2. Create the environment (~2–5 GB disk, ~10–20 min)
#    Using mamba is significantly faster than conda:
mamba env create -f environment.yml
# or: conda env create -f environment.yml

# 3. Activate
conda activate phage_analysis

# 4. Point Nextflow to the bundled Java
export JAVA_HOME=$CONDA_PREFIX
export JAVA_CMD=$CONDA_PREFIX/bin/java

# Verify
nextflow -version
```

Run the pipeline:

```bash
nextflow run cinnetcrash/phage_analysis \
    -profile conda_unified \
    --samplesheet my_samples.csv \
    --kraken2_db  /path/to/kraken2_db \
    --virsorter2_db /path/to/virsorter2_db \
    --checkv_db   /path/to/checkv_db \
    --outdir      results
```

#### Known version notes

| Tool | Note |
|------|------|
| **bacphlip 0.9.6** | Models were trained with scikit-learn 0.23; running with 1.0.x raises `InconsistentVersionWarning` but predictions remain valid. |
| **vHULK** | Requires TensorFlow 2.9 (Python 3.9 compatible); TF 2.8 model weights are forward-compatible. |
| **vContact2** | Requires networkx 2.x API; pinned to `networkx>=2.7,<3.0`. |
| **VirSorter2** | After environment creation, run `virsorter setup -d <db_dir> -j <threads>` to download the database. |

---

### Option B — Docker (single image)

All tools are bundled in a single Docker image built from the same `environment.yml`.

#### Build the image

```bash
git clone https://github.com/cinnetcrash/phage_analysis.git
cd phage_analysis

# Build (~15–30 min, ~8–10 GB image)
docker build -t cinnetcrash/phage_analysis:1.0.0 .

# Or pull from Docker Hub (once published):
docker pull cinnetcrash/phage_analysis:1.0.0
```

#### Run the pipeline

```bash
nextflow run cinnetcrash/phage_analysis \
    -profile docker \
    --samplesheet my_samples.csv \
    --kraken2_db  /path/to/kraken2_db \
    --virsorter2_db /path/to/virsorter2_db \
    --checkv_db   /path/to/checkv_db \
    --outdir      results
```

> Databases are **not** bundled in the image — mount them at runtime via the Nextflow parameters above.  
> Output files are owned by your user (`-u $(id -u):$(id -g)` is applied automatically).

---

### 2. Set up databases

```bash
# Install all databases (~16 GB, ~1–2 h)
bash bin/setup_databases.sh --db-dir ~/phage_databases --threads 8
```

The script prints the exact `nextflow run` command with all paths pre-filled when complete.

**What gets installed:**

| Database | Size | Purpose |
|----------|------|---------|
| Kraken2 viral | ~8 GB | Taxonomic classification |
| VirSorter2 | ~3 GB | Viral sequence detection |
| CheckV | ~3 GB | Genome quality assessment |
| Pharokka | ~2 GB | Phage annotation (E. coli phages) |
| BLAST nt | ~270 GB | Nucleotide identity *(optional — `--install-blast`)* |

**Already have some databases?** Skip them:

```bash
bash bin/setup_databases.sh \
    --db-dir ~/phage_databases \
    --skip-kraken2 \
    --threads 8
```

**Preview without installing:**

```bash
bash bin/setup_databases.sh --db-dir ~/phage_databases --dry-run
```

### 3. Prepare your samplesheet

```bash
cp assets/samplesheet_template.csv my_samples.csv
```

Format (CSV with header row):

```csv
sample_id,host,R1,R2
ECO111_S1,ecoli,/data/ECO111_S1_R1_001.fastq.gz,/data/ECO111_S1_R2_001.fastq.gz
LM-11_S16,listeria,/data/LM-11_S16_R1_001.fastq,/data/LM-11_S16_R2_001.fastq
```

Valid `host` values: `ecoli` · `listeria` · `salmonella` · `enterococcus` · `staphylococcus`

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
| `--min_contig_len` | `1000` | Minimum contig length (bp) |
| `--min_completeness` | `90` | CheckV completeness threshold (%) for DTR/ITR genomes |
| `--skip_virsorter` | `false` | Skip VirSorter2; pass SPAdes contigs directly to CheckV |
| `--skip_kraken2` | `false` | Skip Kraken2 classification |
| `--max_cpus` | `32` | Max CPUs per process |
| `--max_memory` | `128.GB` | Max memory per process |
| `--max_time` | `72.h` | Max wall time per process |

---

## Profiles

| Profile | Description |
|---------|-------------|
| `conda_unified` | **Recommended** — single `phage_analysis` conda env (`environment.yml`) |
| `docker` | Single Docker image (`cinnetcrash/phage_analysis:1.0.0`) |
| `singularity` | Singularity container (HPC-friendly) |
| `conda` | Per-process conda environments (legacy) |
| `slurm` | Submit jobs to a SLURM scheduler |
| `test` | Run with bundled test data |
| `test_local` | Use existing local installation (`conf/test_local.config`) |

---

## Output structure

```
results/
├── fastqc/             FastQC HTML & ZIP reports per sample
├── fastp/              fastp JSON & HTML reports
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
├── phage_pipeline_report.html  Combined HTML summary report
└── pipeline_info/      Nextflow timeline, report & trace files
```

---

## Tools & versions

| Tool | Version | Purpose |
|------|---------|---------|
| FastQC | 0.12.1 | Read quality control |
| fastp | ≥ 0.23 | Adapter trimming & quality filtering |
| Kraken2 | 2.1.3 | Taxonomic classification |
| SPAdes | ≥ 4.0 | Metaviral assembly |
| VirSorter2 | 2.2.4 | Viral sequence identification |
| CheckV | 1.0.1 | Genome completeness assessment |
| BACPHLIP | 0.9.6 | Phage lifestyle prediction |
| Pharokka (Phrokka) | ≥ 1.7.3 | Phage genome annotation |
| Prokka | 1.14.6 | Genome annotation |
| vContact2 | 0.11.3 | Viral taxonomy clustering |
| vHULK | 1.0.0 | Host range prediction |
| BLAST+ | 2.15.0 | Nucleotide identity |
| MultiQC | ≥ 1.21 | QC aggregation |
| Nextflow | ≥ 23.04 | Workflow orchestration |

---

## Citation

If you use this pipeline, please cite the individual tools listed above. A dedicated pipeline citation will be added in a future release.

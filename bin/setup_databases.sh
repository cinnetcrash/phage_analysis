#!/usr/bin/env bash
# =============================================================================
#  phage_analysis — Database Setup Script
#  https://github.com/cinnetcrash/phage_analysis
#
#  Usage:
#    bash bin/setup_databases.sh --db-dir /path/to/databases [options]
#
#  Databases installed:
#    1. Kraken2      (~8 GB  — viral library)
#    2. VirSorter2   (~3 GB)
#    3. CheckV       (~3 GB)
#    4. Pharokka     (~2 GB)
#    5. vHULK        (~2 GB  — neural network models)
#    6. BLAST nt     (~270 GB — optional, very large)
#
#  Total (without BLAST): ~18 GB disk space required.
#
#  Prerequisite: conda environment 'phage_analysis' must be created first:
#    conda env create -f environment.yml
#    conda activate phage_analysis
# =============================================================================
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DB_DIR=""
THREADS=8
ENV_NAME="phage_analysis"
SKIP_KRAKEN2=false
SKIP_VIRSORTER2=false
SKIP_CHECKV=false
SKIP_PHAROKKA=false
SKIP_VHULK=false
INSTALL_BLAST=false
DRY_RUN=false

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: bash bin/setup_databases.sh --db-dir /path/to/databases [options]

Required:
  --db-dir PATH         Directory where databases will be installed

Options:
  --threads N           Number of parallel threads (default: 8)
  --env NAME            Conda environment name (default: phage_analysis)
  --skip-kraken2        Skip Kraken2 DB
  --skip-virsorter2     Skip VirSorter2 DB
  --skip-checkv         Skip CheckV DB
  --skip-pharokka       Skip Pharokka DB
  --skip-vhulk          Skip vHULK DB
  --install-blast       Install BLAST nt DB (~270 GB, takes hours)
  --dry-run             Show what would be done without doing it
  -h, --help            Show this help message

Examples:
  bash bin/setup_databases.sh --db-dir ~/phage_databases --threads 12
  bash bin/setup_databases.sh --db-dir ~/phage_databases --skip-kraken2
  bash bin/setup_databases.sh --db-dir ~/phage_databases --install-blast
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db-dir)          DB_DIR="$2";           shift 2 ;;
        --threads)         THREADS="$2";          shift 2 ;;
        --env)             ENV_NAME="$2";         shift 2 ;;
        --skip-kraken2)    SKIP_KRAKEN2=true;     shift ;;
        --skip-virsorter2) SKIP_VIRSORTER2=true;  shift ;;
        --skip-checkv)     SKIP_CHECKV=true;      shift ;;
        --skip-pharokka)   SKIP_PHAROKKA=true;    shift ;;
        --skip-vhulk)      SKIP_VHULK=true;       shift ;;
        --install-blast)   INSTALL_BLAST=true;    shift ;;
        --dry-run)         DRY_RUN=true;          shift ;;
        -h|--help)         usage ;;
        *) error "Unknown argument: $1  (use --help for usage)" ;;
    esac
done

[[ -z "$DB_DIR" ]] && error "--db-dir is required. Run: bash $0 --help"

# ── Dry-run wrapper ───────────────────────────────────────────────────────────
run() {
    if $DRY_RUN; then
        echo -e "  ${YELLOW}[dry-run]${NC} $*"
    else
        eval "$@"
    fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}"
cat <<'BANNER'
  ____  _                              _               _
 |  _ \| |__   __ _  __ _  ___       / \   _ __   __ _| |_   _ ___ ___ ___
 | |_) | '_ \ / _` |/ _` |/ _ \     / _ \ | '_ \ / _` | | | | / __/ __/ __|
 |  __/| | | | (_| | (_| |  __/    / ___ \| | | | (_| | | |_| \__ \__ \__ \
 |_|   |_| |_|\__,_|\__, |\___|   /_/   \_\_| |_|\__,_|_|\__, |___/___/___/
                     |___/                                 |___/
  Database Setup Script — phage_analysis pipeline
BANNER
echo -e "${NC}"

info "Database directory : ${DB_DIR}"
info "Conda environment  : ${ENV_NAME}"
info "Threads            : ${THREADS}"
$DRY_RUN && warn "DRY-RUN mode — nothing will actually be installed."

# =============================================================================
# Prerequisite: verify conda and phage_analysis env
# =============================================================================
header "Checking prerequisites"

# Find conda/mamba
CONDA_CMD=""
if command -v mamba &>/dev/null; then
    CONDA_CMD="mamba"
    success "mamba found: $(command -v mamba)"
elif command -v conda &>/dev/null; then
    CONDA_CMD="conda"
    success "conda found: $(command -v conda)"
else
    error "conda/mamba not found. Install Miniconda: https://docs.conda.io/en/latest/miniconda.html"
fi

# Source conda init
CONDA_BASE=$(${CONDA_CMD} info --base 2>/dev/null || echo "")
[[ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]] && source "${CONDA_BASE}/etc/profile.d/conda.sh"

# Verify phage_analysis env exists
if ! conda env list 2>/dev/null | grep -qE "^${ENV_NAME}[[:space:]]"; then
    error "Conda environment '${ENV_NAME}' not found.
  Please create it first:
    conda env create -f environment.yml
    # or: mamba env create -f environment.yml"
fi
success "Conda environment '${ENV_NAME}' found."

NF_RUN="conda run -n ${ENV_NAME}"
run mkdir -p "${DB_DIR}"

# =============================================================================
# 1. Kraken2 DB
# =============================================================================
if ! $SKIP_KRAKEN2; then
    header "1/5 · Kraken2 Viral Database (~8 GB)"
    K2_DIR="${DB_DIR}/kraken2_db"

    if [[ -f "${K2_DIR}/taxo.k2d" ]]; then
        success "Kraken2 DB already installed: ${K2_DIR}"
    else
        info "Downloading Kraken2 viral DB → ${K2_DIR}"
        info "This may take 30–60 minutes depending on internet speed."
        run mkdir -p "${K2_DIR}"
        run ${NF_RUN} kraken2-build --download-taxonomy --db "${K2_DIR}" --threads "${THREADS}"
        run ${NF_RUN} kraken2-build --download-library viral --db "${K2_DIR}" --threads "${THREADS}"
        run ${NF_RUN} kraken2-build --build --db "${K2_DIR}" --threads "${THREADS}"
        success "Kraken2 DB installed: ${K2_DIR}"
    fi
fi

# =============================================================================
# 2. VirSorter2 DB
# =============================================================================
if ! $SKIP_VIRSORTER2; then
    header "2/5 · VirSorter2 Database (~3 GB)"
    VS2_DIR="${DB_DIR}/virsorter2_db"

    if [[ -d "${VS2_DIR}/group" ]]; then
        success "VirSorter2 DB already installed: ${VS2_DIR}"
    else
        info "Downloading VirSorter2 DB → ${VS2_DIR}"
        run mkdir -p "${VS2_DIR}"
        run ${NF_RUN} virsorter setup \
            -d "${VS2_DIR}" \
            -j "${THREADS}" \
            --skip-deps-install
        success "VirSorter2 DB installed: ${VS2_DIR}"
    fi
fi

# =============================================================================
# 3. CheckV DB
# =============================================================================
if ! $SKIP_CHECKV; then
    header "3/5 · CheckV Database (~3 GB)"
    CV_DIR="${DB_DIR}/checkv_db"

    if [[ -f "${CV_DIR}/genome_db/checkv_reps.dmnd" ]] || \
       [[ -d "${CV_DIR}/checkv-db-v1.5" ]]; then
        success "CheckV DB already installed: ${CV_DIR}"
    else
        info "Downloading CheckV DB → ${CV_DIR}"
        run mkdir -p "${CV_DIR}"
        run ${NF_RUN} checkv download_database "${CV_DIR}"
        CV_SUB=$(ls -d "${CV_DIR}"/checkv-db-* 2>/dev/null | head -1 || echo "${CV_DIR}")
        success "CheckV DB installed: ${CV_SUB}"
    fi
fi

# =============================================================================
# 4. Pharokka DB
# =============================================================================
if ! $SKIP_PHAROKKA; then
    header "4/5 · Pharokka Database (~2 GB)"
    PH_DIR="${DB_DIR}/pharokka_db"

    if [[ -f "${PH_DIR}/all_phrogs.h3m" ]]; then
        success "Pharokka DB already installed: ${PH_DIR}"
    else
        info "Downloading Pharokka DB → ${PH_DIR}"
        run mkdir -p "${PH_DIR}"
        run ${NF_RUN} install_databases.py -o "${PH_DIR}"
        success "Pharokka DB installed: ${PH_DIR}"
    fi
fi

# =============================================================================
# 5. vHULK DB
# =============================================================================
if ! $SKIP_VHULK; then
    header "5/5 · vHULK Database (~2 GB)"
    VHULK_DIR="${DB_DIR}/vhulk_db"

    if [[ -f "${VHULK_DIR}/all_vogs_hmm_profiles.hmm.h3m" ]]; then
        success "vHULK DB already installed: ${VHULK_DIR}"
    else
        info "Downloading vHULK database → ${VHULK_DIR}"
        info "Source: github.com/LaboratorioBioinformatica/vHULK (database_Aug_2022.tar.gz)"
        run mkdir -p "${VHULK_DIR}"
        run curl -L \
            "https://github.com/LaboratorioBioinformatica/vHULK/raw/master/database_Aug_2022.tar.gz" \
            -o "${VHULK_DIR}/database_Aug_2022.tar.gz"
        run tar -xzf "${VHULK_DIR}/database_Aug_2022.tar.gz" \
            -C "${VHULK_DIR}" --strip-components=1
        run rm "${VHULK_DIR}/database_Aug_2022.tar.gz"
        success "vHULK DB installed: ${VHULK_DIR}"
    fi
fi

# =============================================================================
# 6. BLAST nt (optional, ~270 GB)
# =============================================================================
if $INSTALL_BLAST; then
    header "6/6 · BLAST nt Database (~270 GB — this will take hours)"
    BL_DIR="${DB_DIR}/blast_db"
    warn "BLAST nt download requires ~270 GB disk and several hours."

    if [[ -f "${BL_DIR}/nt.nal" ]]; then
        success "BLAST nt DB already installed: ${BL_DIR}"
    else
        info "Downloading BLAST nt DB → ${BL_DIR}"
        run mkdir -p "${BL_DIR}"
        run "cd '${BL_DIR}' && ${NF_RUN} update_blastdb.pl --decompress --num_threads ${THREADS} nt"
        success "BLAST nt DB installed: ${BL_DIR}"
    fi
fi

# =============================================================================
# Summary — ready-to-run command
# =============================================================================
header "Setup complete!"

# Resolve checkv subdir
CV_ACTUAL="${DB_DIR}/checkv_db"
if ls -d "${DB_DIR}/checkv_db"/checkv-db-* &>/dev/null 2>&1; then
    CV_ACTUAL=$(ls -d "${DB_DIR}/checkv_db"/checkv-db-* | head -1)
fi

echo ""
echo -e "${BOLD}Copy and run the following command:${NC}"
echo ""
echo -e "${GREEN}conda activate ${ENV_NAME}${NC}"
echo -e "${GREEN}export JAVA_HOME=\$CONDA_PREFIX${NC}"
echo -e "${GREEN}export JAVA_CMD=\$CONDA_PREFIX/bin/java${NC}"
echo ""
echo -e "${GREEN}nextflow run cinnetcrash/phage_analysis \\${NC}"
echo -e "${GREEN}    -profile conda_unified \\${NC}"
echo -e "${GREEN}    --samplesheet samplesheet.csv \\${NC}"
$SKIP_KRAKEN2    || echo -e "${GREEN}    --kraken2_db    ${DB_DIR}/kraken2_db \\${NC}"
$SKIP_VIRSORTER2 || echo -e "${GREEN}    --virsorter2_db ${DB_DIR}/virsorter2_db \\${NC}"
$SKIP_CHECKV     || echo -e "${GREEN}    --checkv_db     ${CV_ACTUAL} \\${NC}"
$INSTALL_BLAST   && echo -e "${GREEN}    --blast_db      ${DB_DIR}/blast_db/nt \\${NC}"
echo -e "${GREEN}    --outdir        results${NC}"
echo ""
success "All done!"

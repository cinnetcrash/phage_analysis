#!/usr/bin/env bash
# =============================================================================
#  phage_analysis — Database Setup Script
#  https://github.com/cinnetcrash/phage_analysis
#
#  Kullanım:
#    bash bin/setup_databases.sh --db-dir /path/to/databases [seçenekler]
#
#  Kurulacak veritabanları:
#    1. Kraken2      (~8 GB  — viral library)
#    2. VirSorter2   (~3 GB)
#    3. CheckV       (~3 GB)
#    4. Pharokka     (~2 GB)
#    5. BLAST nt     (~270 GB — opsiyonel, çok büyük)
#
#  Toplam (BLAST hariç): ~16 GB disk alanı gerekir.
#
#  Ön koşul: Miniconda / Mamba kurulu olmalı.
#    https://docs.conda.io/en/latest/miniconda.html
# =============================================================================
set -euo pipefail

# ── Varsayılanlar ─────────────────────────────────────────────────────────────
DB_DIR=""
THREADS=8
SKIP_KRAKEN2=false
SKIP_VIRSORTER2=false
SKIP_CHECKV=false
SKIP_PHAROKKA=false
INSTALL_BLAST=false
DRY_RUN=false

# ── Renk kodları ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}"; }

# ── Argüman ayrıştırma ────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Kullanım: bash bin/setup_databases.sh --db-dir /path/to/databases [seçenekler]

Zorunlu:
  --db-dir PATH         Veritabanlarının kurulacağı ana dizin

Seçenekler:
  --threads N           Paralel iş sayısı (varsayılan: 8)
  --skip-kraken2        Kraken2 DB kurulumunu atla
  --skip-virsorter2     VirSorter2 DB kurulumunu atla
  --skip-checkv         CheckV DB kurulumunu atla
  --skip-pharokka       Pharokka DB kurulumunu atla
  --install-blast       BLAST nt DB'yi kur (~270 GB, uzun sürer)
  --dry-run             Sadece ne yapılacağını göster, kurma
  -h, --help            Bu yardım mesajını göster

Örnek:
  bash bin/setup_databases.sh --db-dir ~/databases --threads 12
  bash bin/setup_databases.sh --db-dir ~/databases --skip-kraken2 --install-blast
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db-dir)          DB_DIR="$2";           shift 2 ;;
        --threads)         THREADS="$2";          shift 2 ;;
        --skip-kraken2)    SKIP_KRAKEN2=true;     shift ;;
        --skip-virsorter2) SKIP_VIRSORTER2=true;  shift ;;
        --skip-checkv)     SKIP_CHECKV=true;      shift ;;
        --skip-pharokka)   SKIP_PHAROKKA=true;    shift ;;
        --install-blast)   INSTALL_BLAST=true;    shift ;;
        --dry-run)         DRY_RUN=true;          shift ;;
        -h|--help)         usage ;;
        *) error "Bilinmeyen argüman: $1  (--help için yardıma bakın)" ;;
    esac
done

[[ -z "$DB_DIR" ]] && error "--db-dir zorunludur. Kullanım için: bash $0 --help"

# ── Dry-run sarmalayıcı ───────────────────────────────────────────────────────
run() {
    if $DRY_RUN; then
        echo -e "  ${YELLOW}[dry-run]${NC} $*"
    else
        eval "$@"
    fi
}

# ── Başlangıç özeti ───────────────────────────────────────────────────────────
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

info "Veritabanı dizini : ${DB_DIR}"
info "Thread sayısı     : ${THREADS}"
$DRY_RUN && warn "DRY-RUN modu aktif — hiçbir şey kurulmayacak."

# =============================================================================
# Conda varlık kontrolü
# =============================================================================
header "Ön Koşul Kontrolü"

CONDA_CMD=""
if command -v mamba &>/dev/null; then
    CONDA_CMD="mamba"
    success "mamba bulundu: $(command -v mamba)"
elif command -v conda &>/dev/null; then
    CONDA_CMD="conda"
    success "conda bulundu: $(command -v conda)"
else
    error "conda/mamba bulunamadı. Lütfen Miniconda kurun: https://docs.conda.io/en/latest/miniconda.html"
fi

# conda init kaynağı
CONDA_BASE=$(${CONDA_CMD} info --base 2>/dev/null || echo "")
if [[ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]]; then
    source "${CONDA_BASE}/etc/profile.d/conda.sh"
fi

# ── Her araç için conda env oluştur (yoksa) ──────────────────────────────────
# Araçları PATH veya belirli env üzerinden çalıştıran yardımcı fonksiyon
ensure_env() {
    local env_name="$1"
    local pkg_spec="$2"   # örn: "bioconda::kraken2"
    local test_cmd="$3"   # kurulu olup olmadığını test eden komut

    if conda env list 2>/dev/null | grep -qE "^${env_name}[[:space:]]"; then
        success "conda env '${env_name}' zaten mevcut."
        return 0
    fi

    info "conda env '${env_name}' oluşturuluyor (${pkg_spec})..."
    run ${CONDA_CMD} create -y -n "${env_name}" -c bioconda -c conda-forge \
        ${pkg_spec} 2>&1 | grep -v "^$" | tail -5
    success "conda env '${env_name}' hazır."
}

run mkdir -p "${DB_DIR}"

# =============================================================================
# 1. Kraken2 DB
# =============================================================================
if ! $SKIP_KRAKEN2; then
    header "1/4 · Kraken2 Viral Database (~8 GB)"
    K2_DIR="${DB_DIR}/kraken2_db"

    if [[ -f "${K2_DIR}/taxo.k2d" ]]; then
        success "Kraken2 DB zaten kurulu: ${K2_DIR}"
    else
        # Araç yoksa kur
        if ! command -v kraken2-build &>/dev/null; then
            if conda env list 2>/dev/null | grep -qE "^kraken2[[:space:]]"; then
                info "kraken2 env mevcut, kullanılıyor."
            else
                ensure_env "kraken2" "kraken2" "kraken2-build"
            fi
            K2_RUN="conda run -n kraken2"
        else
            K2_RUN=""
        fi

        info "Kraken2 viral DB indiriliyor → ${K2_DIR}"
        info "İnternet hızına göre 30–60 dakika sürebilir."
        run mkdir -p "${K2_DIR}"
        run ${K2_RUN} kraken2-build --download-taxonomy --db "${K2_DIR}" --threads "${THREADS}"
        run ${K2_RUN} kraken2-build --download-library viral --db "${K2_DIR}" --threads "${THREADS}"
        run ${K2_RUN} kraken2-build --build --db "${K2_DIR}" --threads "${THREADS}"
        success "Kraken2 DB kuruldu: ${K2_DIR}"
    fi
fi

# =============================================================================
# 2. VirSorter2 DB
# =============================================================================
if ! $SKIP_VIRSORTER2; then
    header "2/4 · VirSorter2 Database (~3 GB)"
    VS2_DIR="${DB_DIR}/virsorter2_db"

    if [[ -d "${VS2_DIR}/group" ]]; then
        success "VirSorter2 DB zaten kurulu: ${VS2_DIR}"
    else
        # Araç yoksa kur
        if ! conda env list 2>/dev/null | grep -qE "^vs2[[:space:]]"; then
            ensure_env "vs2" "virsorter2" "virsorter"
        fi

        info "VirSorter2 DB indiriliyor → ${VS2_DIR}"
        run mkdir -p "${VS2_DIR}"
        run conda run -n vs2 virsorter setup \
            -d "${VS2_DIR}" \
            -j "${THREADS}" \
            --skip-deps-install \
            --conda-frontend conda
        success "VirSorter2 DB kuruldu: ${VS2_DIR}"
    fi
fi

# =============================================================================
# 3. CheckV DB
# =============================================================================
if ! $SKIP_CHECKV; then
    header "3/4 · CheckV Database (~3 GB)"
    CV_DIR="${DB_DIR}/checkv_db"

    if [[ -d "${CV_DIR}/checkv-db-v1.5" ]] || \
       [[ -f "${CV_DIR}/genome_db/checkv_reps.dmnd" ]]; then
        success "CheckV DB zaten kurulu: ${CV_DIR}"
    else
        # Araç yoksa kur
        if ! conda env list 2>/dev/null | grep -qE "^checkv[[:space:]]"; then
            ensure_env "checkv" "checkv" "checkv"
        fi

        info "CheckV DB indiriliyor → ${CV_DIR}"
        run mkdir -p "${CV_DIR}"
        run conda run -n checkv checkv download_database "${CV_DIR}"

        CV_SUB=$(ls -d "${CV_DIR}"/checkv-db-* 2>/dev/null | head -1 || echo "${CV_DIR}")
        success "CheckV DB kuruldu: ${CV_SUB}"
    fi
fi

# =============================================================================
# 4. Pharokka DB
# =============================================================================
if ! $SKIP_PHAROKKA; then
    header "4/4 · Pharokka Database (~2 GB)"
    PH_DIR="${DB_DIR}/pharokka_db"

    if [[ -f "${PH_DIR}/all_phrogs.h3m" ]]; then
        success "Pharokka DB zaten kurulu: ${PH_DIR}"
    else
        # Araç yoksa kur
        if ! conda env list 2>/dev/null | grep -qE "^pharokka[[:space:]]"; then
            ensure_env "pharokka" "pharokka" "pharokka.py"
        fi

        info "Pharokka DB indiriliyor → ${PH_DIR}"
        run mkdir -p "${PH_DIR}"
        run conda run -n pharokka install_databases.py -o "${PH_DIR}"
        success "Pharokka DB kuruldu: ${PH_DIR}"
    fi
fi

# =============================================================================
# 5. BLAST nt (opsiyonel, ~270 GB)
# =============================================================================
if $INSTALL_BLAST; then
    header "5/5 · BLAST nt Database (~270 GB — uzun sürer!)"
    BL_DIR="${DB_DIR}/blast_db"
    warn "BLAST nt indirme işlemi saatler sürebilir ve ~270 GB disk gerektirir."

    if [[ -f "${BL_DIR}/nt.nal" ]]; then
        success "BLAST nt DB zaten kurulu: ${BL_DIR}"
    else
        if ! command -v update_blastdb.pl &>/dev/null; then
            ensure_env "blast" "blast" "blastn"
            BLAST_RUN="conda run -n blast"
        else
            BLAST_RUN=""
        fi
        run mkdir -p "${BL_DIR}"
        run "cd '${BL_DIR}' && ${BLAST_RUN} update_blastdb.pl --decompress --num_threads ${THREADS} nt"
        success "BLAST DB kuruldu: ${BL_DIR}"
    fi
fi

# =============================================================================
# Özet ve hazır komut
# =============================================================================
header "Kurulum Tamamlandı"

echo ""
echo -e "${BOLD}Aşağıdaki komutu kopyalayıp çalıştırabilirsiniz:${NC}"
echo ""
echo -e "${GREEN}nextflow run cinnetcrash/phage_analysis \\${NC}"
echo -e "${GREEN}    -profile conda \\${NC}"
echo -e "${GREEN}    --samplesheet samplesheet.csv \\${NC}"

$SKIP_KRAKEN2    || echo -e "${GREEN}    --kraken2_db    ${DB_DIR}/kraken2_db \\${NC}"
$SKIP_VIRSORTER2 || echo -e "${GREEN}    --virsorter2_db ${DB_DIR}/virsorter2_db \\${NC}"

if ! $SKIP_CHECKV; then
    CV_SUB=$(ls -d "${DB_DIR}/checkv_db"/checkv-db-* 2>/dev/null | head -1 \
             || echo "${DB_DIR}/checkv_db")
    echo -e "${GREEN}    --checkv_db     ${CV_SUB} \\${NC}"
fi

$INSTALL_BLAST && echo -e "${GREEN}    --blast_db      ${DB_DIR}/blast_db/nt \\${NC}"
echo -e "${GREEN}    --outdir        results${NC}"
echo ""
success "Her şey hazır!"

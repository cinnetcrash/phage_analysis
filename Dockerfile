# phage_analysis — single Docker image
# All pipeline tools in one image (Python 3.9, Java 17)
#
# Build:
#   docker build -t cinnetcrash/phage_analysis:1.1.0 .
#
# Push to Docker Hub:
#   docker push cinnetcrash/phage_analysis:1.1.0

FROM condaforge/mambaforge:24.3.0-0

LABEL maintainer="cinnetcrash"
LABEL org.opencontainers.image.source="https://github.com/cinnetcrash/phage_analysis"
LABEL org.opencontainers.image.description="Bacteriophage discovery and characterization pipeline"
LABEL org.opencontainers.image.version="1.1.0"
LABEL org.opencontainers.image.licenses="MIT"

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        procps curl wget unzip pigz less git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── Conda environment (screed + bacphlip dahil) ───────────────────────────────
COPY environment.yml /tmp/environment.yml

RUN mamba env create -f /tmp/environment.yml && \
    mamba clean --all --yes && \
    rm /tmp/environment.yml

# ── vHULK (gultekinunal conda channel) ───────────────────────────────────────
# vhulk kurulumu numpy pinini bozabilir — kurulumdan sonra tekrar sabitle
RUN /opt/conda/bin/conda install -n phage_analysis -y \
        -c gultekinunal -c conda-forge -c bioconda \
        vhulk=2.0.0 && \
    /opt/conda/bin/conda install -n phage_analysis -y \
        "numpy>=1.21,<2.0" && \
    /opt/conda/bin/conda clean --all -y

# ── screed + bacphlip (pip, conda env içinde) ─────────────────────────────────
# --no-build-isolation: conda env'deki setuptools kullanır (pkg_resources sorunu çözülür)
# bacphlip --no-deps: sklearn zaten conda'dan mevcut, tekrar derlenmesine gerek yok
RUN /opt/conda/envs/phage_analysis/bin/pip install --no-build-isolation screed && \
    /opt/conda/envs/phage_analysis/bin/pip install --no-build-isolation --no-deps bacphlip

# ── VirSorter2 sklearn uyumluluk yaması ──────────────────────────────────────
# VirSorter2 modelleri sklearn 0.22.1 ile eğitildi; yüklenen MinMaxScaler
# nesnesi 'clip' attribute içermez. Python başlangıcında otomatik ekliyoruz.
RUN cat > /opt/conda/envs/phage_analysis/lib/python3.9/site-packages/sitecustomize.py << 'EOF'
try:
    from sklearn.preprocessing._data import MinMaxScaler
    _orig_transform = MinMaxScaler.transform
    def _patched_transform(self, X):
        if not hasattr(self, 'clip'):
            self.clip = False
        return _orig_transform(self, X)
    MinMaxScaler.transform = _patched_transform
except Exception:
    pass
EOF

# ── PATH and Java configuration ────────────────────────────────────────────────
ENV PATH="/opt/conda/envs/phage_analysis/bin:${PATH}"
ENV JAVA_HOME="/opt/conda/envs/phage_analysis"
ENV JAVA_CMD="/opt/conda/envs/phage_analysis/bin/java"

SHELL ["/bin/bash", "--login", "-c"]
RUN echo "conda activate phage_analysis" >> ~/.bashrc

# ── Smoke test ────────────────────────────────────────────────────────────────
RUN fastqc --version && \
    fastp --version 2>&1 | head -1 && \
    kraken2 --version | head -1 && \
    spades.py --version && \
    checkv -h 2>&1 | head -1 && \
    pharokka.py --version 2>&1 | head -1 && \
    prokka --version 2>&1 | head -1 && \
    bacphlip --help 2>&1 | head -1 && \
    python3 -c "import screed; print('screed:', screed.__version__)" && \
    python3 -c "from sklearn.preprocessing import MinMaxScaler; m=MinMaxScaler(); m.fit([[0],[1]]); print('sklearn patch: OK')"

WORKDIR /data
CMD ["/bin/bash"]

# phage_analysis — single Docker image
# All pipeline tools in one image (Python 3.9, Java 17, Nextflow included)
#
# Build:
#   docker build -t cinnetcrash/phage_analysis:1.0.0 .
#
# Push to Docker Hub:
#   docker push cinnetcrash/phage_analysis:1.0.0
#
# Run via Nextflow:
#   nextflow run cinnetcrash/phage_analysis -profile docker_unified ...

FROM condaforge/mambaforge:24.3.0-0

LABEL maintainer="cinnetcrash"
LABEL org.opencontainers.image.source="https://github.com/cinnetcrash/phage_analysis"
LABEL org.opencontainers.image.description="Bacteriophage discovery and characterization pipeline"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.licenses="MIT"

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        procps \
        curl \
        wget \
        unzip \
        pigz \
        less \
        git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── Conda environment ─────────────────────────────────────────────────────────
COPY environment.yml /tmp/environment.yml

RUN mamba env create -f /tmp/environment.yml && \
    mamba clean --all --yes && \
    rm /tmp/environment.yml

# ── vHULK (from gultekinunal conda channel) ───────────────────────────────────
RUN /opt/conda/bin/conda install -n phage_analysis -y \
        -c gultekinunal -c conda-forge -c bioconda \
        vhulk=2.0.0 && \
    /opt/conda/bin/conda clean --all -y

# ── PATH and Java configuration ────────────────────────────────────────────────
ENV PATH="/opt/conda/envs/phage_analysis/bin:${PATH}"
ENV JAVA_HOME="/opt/conda/envs/phage_analysis"
ENV JAVA_CMD="/opt/conda/envs/phage_analysis/bin/java"

# Make conda activate work in non-interactive shells
SHELL ["/bin/bash", "--login", "-c"]
RUN echo "conda activate phage_analysis" >> ~/.bashrc

# ── Working directory ─────────────────────────────────────────────────────────
WORKDIR /data

# ── Smoke test ────────────────────────────────────────────────────────────────
RUN fastqc --version && \
    fastp --version 2>&1 | head -1 && \
    kraken2 --version | head -1 && \
    spades.py --version && \
    checkv --version && \
    pharokka.py --version 2>&1 | head -1 && \
    prokka --version 2>&1 | head -1 && \
    nextflow -version | head -3

CMD ["/bin/bash"]

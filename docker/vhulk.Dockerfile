# vHULK — Viral Host Unveiling Kit
# Python 3.7 + TensorFlow 2.8 environment matching the tool's requirements.
#
# Build:
#   docker build -f docker/vhulk.Dockerfile -t cinnetcrash/vhulk:1.0.0 .
#
# Run standalone:
#   docker run --rm -v /path/to/db:/opt/vHULK/database \
#       cinnetcrash/vhulk:1.0.0 \
#       python /opt/vHULK/vHULK.py -i input.fasta -o output/ -t 8

FROM continuumio/miniconda3:23.5.2-0

LABEL maintainer="cinnetcrash"
LABEL org.opencontainers.image.source="https://github.com/cinnetcrash/phage_analysis"
LABEL org.opencontainers.image.description="vHULK — phage host prediction"
LABEL org.opencontainers.image.version="1.0.0"

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends git procps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ── Conda environment ─────────────────────────────────────────────────────────
RUN conda create -n vhulk python=3.7 -y && \
    conda install -n vhulk -y -c conda-forge -c bioconda -c anaconda \
        numpy=1.21.5 \
        pandas=1.3.5 \
        biopython=1.78 \
        scikit-learn=1.0.2 \
        hmmer=3.4 \
        prodigal=2.6.3 \
        "tensorflow=2.8.2" \
        "keras=2.8.0" && \
    conda clean --all -y

# ── vHULK source ──────────────────────────────────────────────────────────────
RUN git clone https://github.com/LaboratorioBioinformatica/vHULK /opt/vHULK && \
    chmod +x /opt/vHULK/vHULK.py

# ── PATH ──────────────────────────────────────────────────────────────────────
ENV PATH="/opt/conda/envs/vhulk/bin:/opt/vHULK:${PATH}"

# ── Database mount point ──────────────────────────────────────────────────────
# Mount the vHULK database directory at runtime:
#   -v /local/vHULK/database:/opt/vHULK/database
VOLUME ["/opt/vHULK/database"]

WORKDIR /data

# ── Smoke test ────────────────────────────────────────────────────────────────
RUN python /opt/vHULK/vHULK.py --help 2>&1 | head -5

CMD ["/bin/bash"]

#!/usr/bin/env python3
"""
Prokka/Phrokka'nın ürettiği .faa dosyalarından vContact2 için
gene_to_genome.csv üretir.

Format:  protein_id,contig_id,keywords
"""

import argparse
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--faa",    required=True, help="Birleştirilmiş all_proteins.faa")
    p.add_argument("--output", required=True, help="Çıktı CSV dosyası")
    p.add_argument("--sep",    default=",",   help="CSV ayırıcı (varsayılan: ',')")
    return p.parse_args()


def main():
    args = parse_args()
    sep = args.sep

    with open(args.faa) as fh, open(args.output, "w") as out:
        out.write(f"protein_id{sep}contig_id{sep}keywords\n")
        for line in fh:
            if not line.startswith(">"):
                continue
            # >LOCUSTAG_00001 ... [genome info]
            parts = line[1:].split()
            protein_id = parts[0]
            # contig_id: proteinin son kısmını at (locus tag prefix'i kullan)
            # Örn: ECO111_00001 → contig ECO111
            underscore_idx = protein_id.rfind("_")
            if underscore_idx > 0:
                contig_id = protein_id[:underscore_idx]
            else:
                contig_id = protein_id
            out.write(f"{protein_id}{sep}{contig_id}{sep}\n")

    print(f"[TAMAM] gene_to_genome CSV yazıldı → {args.output}")


if __name__ == "__main__":
    main()

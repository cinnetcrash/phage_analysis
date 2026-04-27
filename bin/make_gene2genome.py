#!/usr/bin/env python3
"""
Build vContact2 gene_to_genome.csv from Prokka / Pharokka .faa files.

Format:  protein_id,contig_id,keywords

Supported protein ID formats:
  Prokka  : ECO111_00001      → contig ECO111
  Pharokka: TCTTIPOK_CDS_0001 → contig TCTTIPOK
"""

import argparse
import re


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--faa",    required=True, help="Merged all_proteins.faa")
    p.add_argument("--output", required=True, help="Output CSV file")
    p.add_argument("--sep",    default=",",   help="CSV separator (default: ',')")
    return p.parse_args()


def contig_id_from_protein(protein_id: str) -> str:
    """
    Derive genome/contig identifier from a protein locus tag.

    Pharokka: TCTTIPOK_CDS_0001  →  TCTTIPOK  (strip _CDS_NNNN)
    Prokka:   ECO111_00001        →  ECO111    (strip _NNNN)
    """
    # Pharokka pattern: ends with _CDS_digits
    m = re.match(r'^(.+?)_CDS_\d+$', protein_id)
    if m:
        return m.group(1)

    # Prokka pattern: ends with _digits only
    m = re.match(r'^(.+?)_\d+$', protein_id)
    if m:
        return m.group(1)

    # Fallback: return as-is
    return protein_id


def main():
    args = parse_args()
    sep = args.sep

    with open(args.faa) as fh, open(args.output, "w") as out:
        out.write(f"protein_id{sep}contig_id{sep}keywords\n")
        for line in fh:
            if not line.startswith(">"):
                continue
            protein_id = line[1:].split()[0]
            contig_id  = contig_id_from_protein(protein_id)
            out.write(f"{protein_id}{sep}{contig_id}{sep}\n")

    print(f"[OK] gene_to_genome CSV written → {args.output}")


if __name__ == "__main__":
    main()

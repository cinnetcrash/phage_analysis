#!/usr/bin/env python3
"""
CheckV quality_summary.tsv dosyasını okuyarak
circular/complete faj genomlarını filtreler ve
ilgili FASTA kayıtlarını çıkarır.

Kriter:
  - checkv_quality == "Complete"
  - VEYA completeness >= min_completeness (varsayılan 90) VE
         warnings 'DTR' veya 'ITR' içeriyor (circular yapı göstergesi)

Kullanım:
  filter_checkv_circular.py \\
      --summary quality_summary.tsv \\
      --viruses viruses.fna \\
      --proviruses proviruses.fna \\
      --out-fasta filtered_circular.fna \\
      --out-tsv   filtered_circular.tsv \\
      [--min-completeness 90]
"""

import argparse
import sys
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--summary",          required=True, help="CheckV quality_summary.tsv")
    p.add_argument("--viruses",          required=True, help="viruses.fna")
    p.add_argument("--proviruses",       required=True, help="proviruses.fna")
    p.add_argument("--out-fasta",        required=True, help="Çıktı FASTA dosyası")
    p.add_argument("--out-tsv",          required=True, help="Çıktı TSV (filtrelenen satırlar)")
    p.add_argument("--min-completeness", type=float, default=90.0,
                   help="DTR/ITR'li genomlar için minimum tamamlanma yüzdesi (varsayılan: 90)")
    return p.parse_args()


def read_fasta(path):
    """FASTA dosyasını {header_id: sequence} dict olarak döndür."""
    seqs = {}
    current_id = None
    current_seq = []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip()
            if line.startswith(">"):
                if current_id is not None:
                    seqs[current_id] = "".join(current_seq)
                # Sadece boşluğa kadar olan kısmı ID olarak al
                current_id = line[1:].split()[0]
                current_seq = []
            else:
                current_seq.append(line)
    if current_id is not None:
        seqs[current_id] = "".join(current_seq)
    return seqs


def is_circular(row: dict, min_completeness: float) -> bool:
    """
    Satırın circular/complete kritere uyup uymadığını döndür.
    """
    quality = row.get("checkv_quality", "").strip()
    if quality in ("Complete", "High-quality"):
        return True

    # Tamamlanma yüzdesi kontrolü
    try:
        completeness = float(row.get("completeness", 0) or 0)
    except ValueError:
        completeness = 0.0

    warnings = row.get("warnings", "").upper()
    has_circular_marker = "DTR" in warnings or "ITR" in warnings

    if completeness >= min_completeness and has_circular_marker:
        return True

    return False


def main():
    args = parse_args()

    # FASTA kayıtlarını yükle
    all_seqs = {}
    for fa_path in [args.viruses, args.proviruses]:
        if Path(fa_path).is_file() and Path(fa_path).stat().st_size > 0:
            all_seqs.update(read_fasta(fa_path))

    if not all_seqs:
        print("[UYARI] Hiç FASTA kaydı bulunamadı. Boş çıktı üretiliyor.", file=sys.stderr)
        open(args.out_fasta, "w").close()
        open(args.out_tsv, "w").close()
        sys.exit(0)

    # quality_summary.tsv oku
    selected_ids = []
    header_line = None
    rows = []

    with open(args.summary) as fh:
        for i, line in enumerate(fh):
            line = line.rstrip("\n")
            if i == 0:
                header_line = line
                columns = line.split("\t")
                continue
            fields = line.split("\t")
            row = dict(zip(columns, fields))
            rows.append((row, line))

    if not rows:
        print("[UYARI] quality_summary.tsv boş!", file=sys.stderr)
        open(args.out_fasta, "w").close()
        open(args.out_tsv, "w").close()
        sys.exit(0)

    # Filtrele
    circular_rows = []
    for row, raw_line in rows:
        if is_circular(row, args.min_completeness):
            contig_id = row.get("contig_id", "").split()[0]
            selected_ids.append(contig_id)
            circular_rows.append(raw_line)

    print(f"[BİLGİ] Toplam contig: {len(rows)}, "
          f"Circular/Complete seçilen: {len(selected_ids)}", file=sys.stderr)

    if not selected_ids:
        print("[UYARI] Hiçbir circular/complete genom seçilmedi!", file=sys.stderr)
        open(args.out_fasta, "w").close()
        # Başlık satırıyla birlikte boş TSV
        with open(args.out_tsv, "w") as fh:
            fh.write(header_line + "\n")
        sys.exit(0)

    # FASTA yaz
    missing = []
    with open(args.out_fasta, "w") as out:
        for seq_id in selected_ids:
            if seq_id in all_seqs:
                out.write(f">{seq_id}\n{all_seqs[seq_id]}\n")
            else:
                missing.append(seq_id)

    if missing:
        print(f"[UYARI] {len(missing)} contig_id FASTA'da bulunamadı: "
              f"{', '.join(missing[:5])}{'...' if len(missing) > 5 else ''}", file=sys.stderr)

    # TSV yaz
    with open(args.out_tsv, "w") as fh:
        fh.write(header_line + "\n")
        for line in circular_rows:
            fh.write(line + "\n")

    print(f"[TAMAM] {len(selected_ids) - len(missing)} sekans yazıldı → {args.out_fasta}",
          file=sys.stderr)


if __name__ == "__main__":
    main()

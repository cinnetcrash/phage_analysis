#!/usr/bin/env python3
"""
Generate a combined HTML summary report from phage pipeline outputs.
"""

import argparse
import json
import sys
from pathlib import Path
from datetime import datetime


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--results-dir", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--pipeline-version", default="1.0")
    return p.parse_args()


def fmt_int(v):
    return f"{v:,}" if isinstance(v, int) else str(v)


def badge(text, color):
    return (f'<span style="background:{color};color:#fff;padding:2px 8px;'
            f'border-radius:4px;font-size:0.84em">{text}</span>')


QUALITY_COLORS = {
    "Complete":       "#2ecc71",
    "High-quality":   "#27ae60",
    "Medium-quality": "#f39c12",
    "Low-quality":    "#e74c3c",
    "Not-determined": "#95a5a6",
}


def quality_badge(q):
    return badge(q, QUALITY_COLORS.get(q, "#95a5a6"))


def lifecycle_badge(row):
    vals = list(row.values())
    try:
        vir = float(vals[1])
        tmp = float(vals[2])
    except Exception:
        return badge("N/A", "#95a5a6")
    if vir >= 0.5:
        return badge(f"Lytic ({vir:.2f})", "#e74c3c")
    return badge(f"Lysogenic ({tmp:.2f})", "#8e44ad")


# ── loaders ──────────────────────────────────────────────────────────────────

def load_fastp(results_dir):
    stats = {}
    for jf in Path(results_dir, "fastp").rglob("*_fastp.json"):
        sample = jf.stem.replace("_fastp", "")
        try:
            d = json.loads(jf.read_text())
            af = d["summary"]["after_filtering"]
            bf = d["summary"]["before_filtering"]
            stats[sample] = {
                "reads_before": bf["total_reads"],
                "reads_after":  af["total_reads"],
                "q30":          round(af["q30_rate"] * 100, 1),
                "gc":           round(af["gc_content"] * 100, 1),
            }
        except Exception:
            stats[sample] = {}
    return stats


def load_tsv(path):
    lines = Path(path).read_text().splitlines()
    if len(lines) < 2:
        return []
    header = lines[0].split("\t")
    rows = []
    for line in lines[1:]:
        if line.strip():
            rows.append(dict(zip(header, line.split("\t"))))
    return rows


def load_checkv(results_dir):
    data = {}
    # sadece checkv/<sample>/quality_summary.tsv — iç içe checkv_results/ klasörünü atlat
    for tsv in Path(results_dir, "checkv").glob("*/quality_summary.tsv"):
        sample = tsv.parent.name
        try:
            data[sample] = load_tsv(tsv)
        except Exception:
            data[sample] = []
    return data


def load_circular(results_dir):
    data = {}
    for tsv in Path(results_dir, "checkv_filtered").glob("*/filtered_circular.tsv"):
        sample = tsv.parent.name
        try:
            data[sample] = load_tsv(tsv)
        except Exception:
            data[sample] = []
    return data


def load_bacphlip(results_dir):
    data = {}
    for tsv in Path(results_dir, "bacphlip").rglob("*_bacphlip.tsv"):
        try:
            rows = load_tsv(tsv)
            for row in rows:
                vals = list(row.values())
                if vals:
                    data[vals[0]] = row
        except Exception:
            pass
    return data


def load_vhulk(results_dir):
    data = {}
    for tsv in Path(results_dir, "vhulk").rglob("*_vhulk_predictions.tsv"):
        try:
            rows = load_tsv(tsv)
            for row in rows:
                vals = list(row.values())
                if vals:
                    data[vals[0]] = row
        except Exception:
            pass
    return data


# ── HTML rendering ────────────────────────────────────────────────────────────

CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
       background: #f0f2f5; color: #333; }
header { background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
         color: white; padding: 32px 40px; }
header h1 { font-size: 2em; font-weight: 700; }
header p  { opacity: 0.7; margin-top: 6px; font-size: 0.95em; }
.container { max-width: 1300px; margin: 0 auto; padding: 32px 24px; }
.stats-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 32px; }
.stat-card { background: white; border-radius: 12px; padding: 20px 24px;
             box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
.stat-card .value { font-size: 2.4em; font-weight: 700; color: #0f3460; }
.stat-card .label { color: #888; font-size: 0.9em; margin-top: 4px; }
.card { background: white; border-radius: 12px; padding: 24px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 24px; }
.card h2 { font-size: 1.2em; color: #1a1a2e; margin-bottom: 16px;
           padding-bottom: 10px; border-bottom: 2px solid #f0f2f5; }
.card h3 { font-size: 1em; font-weight: 600; margin-bottom: 12px; color: #444; }
table { width: 100%; border-collapse: collapse; font-size: 0.9em; }
th { background: #f8f9fa; padding: 10px 12px; text-align: left;
     font-weight: 600; color: #555; border-bottom: 2px solid #e9ecef; }
td { padding: 9px 12px; border-bottom: 1px solid #f0f2f5; vertical-align: middle; }
tr:hover td { background: #fafbfc; }
footer { text-align: center; padding: 24px; color: #aaa; font-size: 0.85em; }
"""


def render_summary_row(r):
    fp = r["fp"]
    qc = r["qual_counts"]

    def qbadge(key, color, label):
        n = qc.get(key, 0)
        return f'<span style="color:{color}"><b>{n}</b> {label}</span>' if n else ""

    qc_parts = list(filter(None, [
        qbadge("Complete",       "#2ecc71", "Complete"),
        qbadge("High-quality",   "#27ae60", "High"),
        qbadge("Medium-quality", "#f39c12", "Med"),
        qbadge("Low-quality",    "#e74c3c", "Low"),
    ]))
    qc_str = " &nbsp; ".join(qc_parts) if qc_parts else "—"

    n_circ = r["n_circular"]
    circ_cell = badge(str(n_circ), "#2980b9") if n_circ > 0 else "0"

    return (
        f"<tr>"
        f"<td><b>{r['sample']}</b></td>"
        f"<td>{fmt_int(fp.get('reads_before', '—'))}</td>"
        f"<td>{fmt_int(fp.get('reads_after', '—'))}</td>"
        f"<td>{fp.get('q30', '—')}%</td>"
        f"<td>{fp.get('gc', '—')}%</td>"
        f"<td>{fmt_int(r['total_contigs'])}</td>"
        f"<td>{circ_cell}</td>"
        f"<td style='font-size:0.85em'>{qc_str}</td>"
        f"</tr>"
    )


def render_detail_section(r, bacphlip, vhulk):
    contigs = r["circ_contigs"]
    if not contigs:
        return ""

    rows_html = []
    for c in contigs:
        cid     = c.get("contig_id", "")
        length  = c.get("contig_length", c.get("length", "—"))
        quality = c.get("checkv_quality", "—")
        compl   = c.get("completeness", "—")
        warns   = c.get("warnings", "—")

        bp_row = bacphlip.get(cid, {})
        vh_row = vhulk.get(cid, {})

        # vHULK predicted host — try common column names
        ph = "—"
        for key in ("Predicted_Host", "predicted_host", "host"):
            if key in vh_row:
                ph = vh_row[key]
                break
        if ph == "—" and len(vh_row) > 1:
            ph = list(vh_row.values())[1]

        try:
            len_str = f"{int(length):,} bp"
        except Exception:
            len_str = str(length)

        lc_cell = lifecycle_badge(bp_row) if bp_row else badge("—", "#ccc")

        rows_html.append(
            f"<tr>"
            f"<td style='font-family:monospace;font-size:0.84em'>{cid}</td>"
            f"<td>{len_str}</td>"
            f"<td>{quality_badge(quality)}</td>"
            f"<td>{compl}%</td>"
            f"<td>{warns}</td>"
            f"<td>{lc_cell}</td>"
            f"<td>{ph}</td>"
            f"</tr>"
        )

    tbody = "".join(rows_html)
    return f"""
    <div style="margin-bottom:24px">
      <h3>&#129418; {r['sample']} — Circular/Complete Phage Genomes ({len(contigs)})</h3>
      <table>
        <thead><tr>
          <th>Contig ID</th><th>Length</th><th>CheckV Quality</th>
          <th>Completeness</th><th>Warnings</th><th>Lifecycle</th><th>Predicted Host</th>
        </tr></thead>
        <tbody>{tbody}</tbody>
      </table>
    </div>"""


def render_html(rows, bacphlip, vhulk, version):
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    total_samples   = len(rows)
    total_circular  = sum(r["n_circular"] for r in rows)
    with_phage      = sum(1 for r in rows if r["n_circular"] > 0)

    summary_rows  = "".join(render_summary_row(r) for r in rows)
    detail_cards  = "".join(render_detail_section(r, bacphlip, vhulk) for r in rows)

    if not detail_cards.strip():
        detail_cards = ('<p style="color:#888;padding:16px 0">'
                        'No circular or complete phage genomes identified in this run.</p>')

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Phage Pipeline Report</title>
<style>{CSS}</style>
</head>
<body>
<header>
  <h1>&#128300; Phage Pipeline Report</h1>
  <p>Generated: {now} &nbsp;&middot;&nbsp; Pipeline v{version} &nbsp;&middot;&nbsp; {total_samples} samples</p>
</header>
<div class="container">

  <div class="stats-grid">
    <div class="stat-card">
      <div class="value">{total_samples}</div>
      <div class="label">Samples processed</div>
    </div>
    <div class="stat-card">
      <div class="value">{with_phage}</div>
      <div class="label">Samples with circular phages</div>
    </div>
    <div class="stat-card">
      <div class="value">{total_circular}</div>
      <div class="label">Total circular / complete phage genomes</div>
    </div>
  </div>

  <div class="card">
    <h2>&#128202; Per-Sample Summary</h2>
    <table>
      <thead><tr>
        <th>Sample</th>
        <th>Reads (raw)</th><th>Reads (trimmed)</th>
        <th>Q30</th><th>GC%</th>
        <th>Contigs</th><th>Circular Phages</th>
        <th>CheckV Quality</th>
      </tr></thead>
      <tbody>{summary_rows}</tbody>
    </table>
  </div>

  <div class="card">
    <h2>&#129514; Circular / Complete Phage Genomes</h2>
    {detail_cards}
  </div>

</div>
<footer>phage_analysis pipeline &nbsp;&middot;&nbsp; {now}</footer>
</body>
</html>"""


def main():
    args = parse_args()
    results = Path(args.results_dir)

    fastp    = load_fastp(results)
    checkv   = load_checkv(results)
    circular = load_circular(results)
    bacphlip = load_bacphlip(results)
    vhulk    = load_vhulk(results)

    all_samples = sorted(set(list(fastp) + list(checkv) + list(circular)))

    rows = []
    for sid in all_samples:
        fp          = fastp.get(sid, {})
        cv_rows     = checkv.get(sid, [])
        circ_rows   = circular.get(sid, [])
        qual_counts = {}
        for r in cv_rows:
            q = r.get("checkv_quality", "Unknown")
            qual_counts[q] = qual_counts.get(q, 0) + 1

        rows.append({
            "sample":        sid,
            "fp":            fp,
            "total_contigs": len(cv_rows),
            "n_circular":    len(circ_rows),
            "qual_counts":   qual_counts,
            "circ_contigs":  circ_rows,
        })

    html = render_html(rows, bacphlip, vhulk, args.pipeline_version)
    Path(args.output).write_text(html)

    n_circ = sum(r["n_circular"] for r in rows)
    print(f"[OK] Report → {args.output}  ({len(rows)} samples, {n_circ} circular phages)")


if __name__ == "__main__":
    main()

"""Print the measured-data result tables (markdown) from experiments/results/v1.

  python experiments/make_results_table.py

Table 1: mean ± std over the 5 seeds and the summed confusion counts (summary.json).
Table 2: false positives per non-fall label, from predictions.csv joined with
dataset/metadata/windows.csv (is_fall == 0 and p_fall >= threshold), summed over seeds.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "experiments" / "results" / "v1"
WINDOWS = ROOT / "dataset" / "metadata" / "windows.csv"

# name, table-1 title, table-2 column title
RUNS = [
    ("b1_random", "1·2차 수집 (07-08·07-09) 1,019개", "1·2차 수집 1,019개"),
    ("random_all", "전체 (07-08–07-28) 2,217개", "전체 2,217개"),
]
METRICS = ("recall", "precision", "f1", "auroc")
CATEGORY_ORDER = {"confusing": 0, "daily": 1}


def fmt(stat: dict) -> str:
    return f"{stat['mean']:.3f}" if stat["std"] < 0.0005 else f"{stat['mean']:.3f} ± {stat['std']:.3f}"


def load_summary(name: str) -> dict:
    return json.loads((RESULTS / name / "summary.json").read_text(encoding="utf-8"))


def false_positives(name: str, meta: dict[str, dict], threshold: float) -> tuple[Counter, Counter]:
    tested, flagged = Counter(), Counter()
    with (RESULTS / name / "predictions.csv").open(encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            window = meta[row["window_id"]]
            if window["is_fall"] != "0":
                continue
            tested[window["label"]] += 1
            flagged[window["label"]] += float(row["p_fall"]) >= threshold
    return tested, flagged


def main() -> None:
    argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter).parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    summaries = {name: load_summary(name) for name, *_ in RUNS}

    print("| 데이터 | 시험 윈도우(5회 합계) | 낙상 재현율 | 정밀도 | F1 | AUROC | TP | FP | TN | FN |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for name, title, _ in RUNS:
        s = summaries[name]["summary"]
        total = s["tp"] + s["fp"] + s["tn"] + s["fn"]
        values = " | ".join(fmt(s[m]) for m in METRICS)
        counts = " | ".join(f"{s[k]:,}" for k in ("tp", "fp", "tn", "fn"))
        print(f"| {title} | {total:,} | {values} | {counts} |")
    print()

    with WINDOWS.open(encoding="utf-8") as handle:
        meta = {row["window_id"]: row for row in csv.DictReader(handle)}
    labels = {row["label"]: (row["label_ko"], row["category"]) for row in meta.values() if row["is_fall"] == "0"}
    flags = {name: false_positives(name, meta, summaries[name]["threshold"]) for name, *_ in RUNS}

    print("| 구분 | 동작 | " + " | ".join(f"{short} 오탐 / 시험" for *_, short in RUNS) + " |")
    print("|---|---|" + "---:|" * len(RUNS))
    for label, (label_ko, category) in sorted(labels.items(), key=lambda kv: (CATEGORY_ORDER[kv[1][1]], kv[1][0])):
        cells = []
        for name, *_ in RUNS:
            tested, flagged = flags[name]
            cells.append(f"{flagged[label]} / {tested[label]}" if tested[label] else "-")
        group = "혼동 동작" if category == "confusing" else "일상 동작"
        print(f"| {group} | {label_ko} | " + " | ".join(cells) + " |")
    totals = [f"{sum(flags[n][1].values()):,} / {sum(flags[n][0].values()):,}" for n, *_ in RUNS]
    print("| 합계 | | " + " | ".join(totals) + " |")


if __name__ == "__main__":
    main()

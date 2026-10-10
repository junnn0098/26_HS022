"""Compare CSI respiratory output with manually aligned reference measurements.

CSV columns: predicted_bpm,reference_bpm. Optional Boolean columns
apnea_suspected and apnea_reference add an event-level confusion matrix.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np


def boolean(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "y"}


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate respiratory rate against a reference")
    parser.add_argument("csv_file", type=Path)
    parser.add_argument("--output", type=Path, default=Path("reports/respiratory_reference.json"))
    args = parser.parse_args()
    with args.csv_file.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        parser.error("reference CSV has no rows")
    valid = [
        row for row in rows
        if row.get("predicted_bpm", "").strip() and row.get("reference_bpm", "").strip()
    ]
    if not valid:
        parser.error("no rows contain both predicted_bpm and reference_bpm")
    predicted = np.asarray([float(row["predicted_bpm"]) for row in valid], dtype=np.float64)
    reference = np.asarray([float(row["reference_bpm"]) for row in valid], dtype=np.float64)
    error = predicted - reference
    result = {
        "schema": "hanium.ruview.respiratory-reference-evaluation.v1",
        "rows": len(rows),
        "paired_bpm_rows": len(valid),
        "coverage": round(len(valid) / len(rows), 6),
        "mae_bpm": round(float(np.mean(np.abs(error))), 6),
        "rmse_bpm": round(float(np.sqrt(np.mean(error ** 2))), 6),
        "bias_bpm": round(float(np.mean(error)), 6),
        "note": "research evaluation only; not a medical-device validation",
    }
    apnea_rows = [
        row for row in rows
        if row.get("apnea_suspected", "").strip() and row.get("apnea_reference", "").strip()
    ]
    if apnea_rows:
        predicted_apnea = np.asarray([boolean(row["apnea_suspected"]) for row in apnea_rows])
        reference_apnea = np.asarray([boolean(row["apnea_reference"]) for row in apnea_rows])
        true_positive = int(np.count_nonzero(predicted_apnea & reference_apnea))
        false_positive = int(np.count_nonzero(predicted_apnea & ~reference_apnea))
        false_negative = int(np.count_nonzero(~predicted_apnea & reference_apnea))
        true_negative = int(np.count_nonzero(~predicted_apnea & ~reference_apnea))
        result["apnea"] = {
            "rows": len(apnea_rows),
            "true_positive": true_positive,
            "false_positive": false_positive,
            "false_negative": false_negative,
            "true_negative": true_negative,
            "sensitivity": round(true_positive / max(true_positive + false_negative, 1), 6),
            "specificity": round(true_negative / max(true_negative + false_positive, 1), 6),
        }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f"REPORT={args.output.resolve()}")
    print("RESULT=PASS_RESPIRATORY_REFERENCE_EVALUATION")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

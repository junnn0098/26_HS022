"""Apply explicit release gates to cough and overnight false-alarm results."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Check cough model release criteria")
    parser.add_argument("report", type=Path)
    parser.add_argument("--min-cough-precision", type=float, default=0.90)
    parser.add_argument("--min-cough-recall", type=float, default=0.90)
    parser.add_argument("--min-macro-f1", type=float, default=0.80)
    parser.add_argument("--reviewed-negative-hours", type=float, default=0.0)
    parser.add_argument("--false-confirmed-coughs", type=int, default=0)
    parser.add_argument("--max-false-coughs-per-hour", type=float, default=0.10)
    args = parser.parse_args()
    if args.reviewed_negative_hours < 0 or args.false_confirmed_coughs < 0:
        parser.error("reviewed hours and false counts must be non-negative")
    report = json.loads(args.report.read_text(encoding="utf-8"))
    classification = report["classification"]
    cough = classification["per_class"]["cough"]
    checks = {
        "cough_precision": {"value": float(cough["precision"]), "minimum": args.min_cough_precision},
        "cough_recall": {"value": float(cough["recall"]), "minimum": args.min_cough_recall},
        "cough_test_support": {"value": int(cough["support"]), "minimum": 1},
        "macro_f1": {"value": float(classification["macro_f1"]), "minimum": args.min_macro_f1},
    }
    failures = [
        name for name, item in checks.items()
        if item["value"] < item["minimum"]
    ]
    if args.reviewed_negative_hours > 0:
        rate = args.false_confirmed_coughs / args.reviewed_negative_hours
        checks["false_confirmed_coughs_per_hour"] = {
            "value": round(rate, 6),
            "maximum": args.max_false_coughs_per_hour,
            "reviewed_hours": args.reviewed_negative_hours,
        }
        if rate > args.max_false_coughs_per_hour:
            failures.append("false_confirmed_coughs_per_hour")
    result = {"checks": checks, "failures": failures}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if failures:
        print("RESULT=FAIL_COUGH_RELEASE_GATES")
        return 2
    print("RESULT=PASS_COUGH_RELEASE_GATES")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

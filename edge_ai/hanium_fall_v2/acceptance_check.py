"""Apply explicit release gates to a held-out evaluation report."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Check model release criteria")
    parser.add_argument("report", type=Path)
    parser.add_argument("--min-display-macro-f1", type=float, default=0.90)
    parser.add_argument("--min-fall-recall", type=float, default=0.95)
    parser.add_argument("--min-count-macro-f1", type=float, default=0.80)
    parser.add_argument("--reviewed-negative-hours", type=float, default=0.0)
    parser.add_argument("--observed-false-alarms", type=int, default=0)
    parser.add_argument("--max-false-alarms-per-day", type=float, default=1.0)
    args = parser.parse_args()

    if args.reviewed_negative_hours < 0 or args.observed_false_alarms < 0:
        parser.error("reviewed hours and false alarms must be non-negative")
    report = json.loads(args.report.read_text(encoding="utf-8"))
    display = report["display_activity"]
    count = report["count"]
    fall = display["per_class"]["fall"]
    checks = {
        "display_macro_f1": {
            "value": float(display["macro_f1"]),
            "minimum": args.min_display_macro_f1,
        },
        "fall_recall": {
            "value": float(fall["recall"]),
            "minimum": args.min_fall_recall,
        },
        "fall_test_support": {
            "value": int(fall["support"]),
            "minimum": 1,
        },
        "count_macro_f1": {
            "value": float(count["macro_f1"]),
            "minimum": args.min_count_macro_f1,
        },
    }
    failures = [
        name for name, item in checks.items() if item["value"] < item["minimum"]
    ]
    false_alarm_rate = None
    if args.reviewed_negative_hours > 0:
        false_alarm_rate = args.observed_false_alarms * 24.0 / args.reviewed_negative_hours
        checks["false_alarms_per_day"] = {
            "value": round(false_alarm_rate, 6),
            "maximum": args.max_false_alarms_per_day,
            "reviewed_hours": args.reviewed_negative_hours,
        }
        if false_alarm_rate > args.max_false_alarms_per_day:
            failures.append("false_alarms_per_day")

    result = {
        "report": str(args.report.resolve()),
        "checks": checks,
        "failures": failures,
        "note": (
            "False-alarm rate was not checked; run a reviewed negative trial."
            if false_alarm_rate is None
            else "False-alarm rate is based on manually reviewed negative hours."
        ),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if failures:
        print("RESULT=FAIL_MODEL_RELEASE_GATES")
        return 2
    print("RESULT=PASS_MODEL_RELEASE_GATES")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

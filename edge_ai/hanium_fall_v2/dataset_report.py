"""Summarize class and person-count coverage across recorded sessions."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

import numpy as np

from .labels import ACTIVITIES


def main() -> int:
    parser = argparse.ArgumentParser(description="Report dataset coverage")
    parser.add_argument("capture_dir", type=Path)
    args = parser.parse_args()

    files = sorted(args.capture_dir.glob("*.npz"))
    if not files:
        print(f"RESULT=FAIL_NO_CAPTURES path={args.capture_dir}")
        return 2

    coverage: defaultdict[tuple[str, str], dict[str, float]] = defaultdict(
        lambda: {"sessions": 0, "minutes": 0.0, "frames": 0}
    )
    bad_files: list[str] = []
    for path in files:
        try:
            with np.load(path, allow_pickle=False) as data:
                meta = json.loads(str(data["meta_json"].item()))
                key = (str(meta["activity"]), str(meta["people_bucket"]))
                coverage[key]["sessions"] += 1
                coverage[key]["minutes"] += float(meta["capture_elapsed_seconds"]) / 60.0
                coverage[key]["frames"] += int(data["iq"].shape[0])
        except Exception as exc:
            bad_files.append(f"{path}: {exc}")

    print("activity          people  sessions  minutes  frames")
    print("----------------  ------  --------  -------  ------")
    for activity in ACTIVITIES:
        buckets = sorted(
            ((bucket, values) for (name, bucket), values in coverage.items() if name == activity),
            key=lambda item: item[0],
        )
        for bucket, values in buckets:
            print(
                f"{activity:<16}  {bucket:<6}  {int(values['sessions']):>8}  "
                f"{values['minutes']:>7.2f}  {int(values['frames']):>6}"
            )
    print(f"TOTAL_FILES={len(files)} BAD_FILES={len(bad_files)}")
    for item in bad_files:
        print(f"BAD_FILE={item}")
    print("RESULT=PASS_DATASET_REPORT" if not bad_files else "RESULT=FAIL_BAD_FILES")
    return 0 if not bad_files else 3


if __name__ == "__main__":
    raise SystemExit(main())


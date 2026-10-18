"""Publish aggregate statistics from the repository's collection metadata only."""
from __future__ import annotations

import argparse
from collections import Counter
import csv
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import statistics

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/data_collection/collection_log.csv"
plt.rcParams.update({"svg.fonttype": "none", "svg.hashsalt": "hanium-aggregate-audit",
                     "axes.spines.top": False, "axes.spines.right": False, "font.size": 11})


def aggregate_records(source: Path) -> dict:
    with source.open(encoding="utf-8-sig", newline="") as stream:
        records = list(csv.DictReader(stream))
    if not records:
        raise ValueError("Collection metadata must contain at least one record.")
    kst = timezone(timedelta(hours=9))
    categories = Counter(row["category"] for row in records)
    unknown = sum(row["subject"].strip() in ("", "-") for row in records)
    offsets, timestamp_mismatches = [], 0
    for row in records:
        epoch = int(row["csi_file"].split("-")[1].split(".")[0])
        csi_time = datetime.fromtimestamp(epoch, kst)
        listed = datetime.fromisoformat(row["date"] + "T" + row["csi_start_kst"]).replace(tzinfo=kst)
        timestamp_mismatches += csi_time != listed
        if row["keypoints_file"]:
            paired = datetime.strptime(row["keypoints_file"], "keypoints_%Y%m%d_%H%M%S.jsonl").replace(tzinfo=kst)
            offsets.append((paired - csi_time).total_seconds())
    return {
        "scope": "Aggregate metadata only; not raw recordings, model evaluation clips, or participant-level results.",
        "source_path": str(source.relative_to(ROOT)),
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "records": len(records),
        "collection_rounds": len({row["session"] for row in records}),
        "categories": dict(sorted(categories.items())),
        "records_with_subject_id": len(records) - unknown,
        "records_without_subject_id": unknown,
        "records_with_paired_filename": len(offsets),
        "duplicate_csi_filenames": len(records) - len({row["csi_file"] for row in records}),
        "epoch_kst_mismatches": timestamp_mismatches,
        "paired_start_offset_seconds": {
            "minimum": min(offsets) if offsets else None,
            "median": statistics.median(offsets) if offsets else None,
            "maximum": max(offsets) if offsets else None,
        },
    }


def plot_summary(summary: dict, target: Path) -> None:
    keys = ("낙상", "혼동 동작", "일상")
    if set(summary["categories"]) - set(keys):
        raise ValueError("New category found: update the plot labels before publishing.")
    counts = [summary["categories"].get(key, 0) for key in keys]
    fig, ax = plt.subplots(figsize=(8, 4.2), constrained_layout=True)
    bars = ax.barh(["Fall", "Confounding actions", "Daily activities"], counts,
                   color=["#bc7040", "#7f99ab", "#14847d"], height=0.58)
    for bar, count in zip(bars, counts):
        ax.text(count + 0.3, bar.get_y() + bar.get_height() / 2,
                f"{count} ({count / summary['records']:.1%})", va="center")
    ax.set_xlim(0, max(counts) * 1.35)
    ax.set_xlabel("Recording metadata rows / not evaluation clips")
    ax.set_title(f"Published collection inventory: {summary['records']} records", loc="left", fontweight="bold")
    ax.xaxis.set_major_locator(matplotlib.ticker.MaxNLocator(integer=True))
    fig.savefig(target, bbox_inches="tight", metadata={"Date": None})
    target.write_text("\n".join(line.rstrip() for line in target.read_text(encoding="utf-8").splitlines()) + "\n", encoding="utf-8")
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "experiments/results/local/collection")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    summary = aggregate_records(SOURCE)
    (args.output / "collection_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    plot_summary(summary, args.output / "collection_distribution.svg")
    print(json.dumps({"records": summary["records"], "categories": summary["categories"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()

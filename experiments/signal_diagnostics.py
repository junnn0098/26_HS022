"""Does the measured CSI change with the person's activity?

For every 5-second training window this computes a model-free motion statistic from
the v2 sessions (first LLTF block, per node, common-mode gain removed): the mean over
subcarriers of the temporal standard deviation of log amplitude. If CSI captured the
motion well, windows of walking/falling would score clearly higher than sitting,
standing or lying in the same session. Results are split by packet width, because
the nodes send 64/128/192-value packets whose LLTF blocks behave differently.

  python experiments/signal_diagnostics.py --sessions dataset/v2_sessions
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "edge_ai"))

from hanium_fall_v1.data import read_metadata  # noqa: E402
from hanium_fall_v1.metrics import auroc  # noqa: E402

STATIC = {"sitting", "standing", "lying"}
WIDTHS = ("all", "128", "192")


def window_statistic(times, nodes, widths, amplitude, start: float, width: str) -> float:
    values = []
    inside = (times >= start) & (times < start + 5.0)
    for node in (1, 2, 3, 4):
        mask = inside & (nodes == node)
        if width != "all":
            mask &= widths == int(width)
        if mask.sum() < 15:
            continue
        block = amplitude[mask]
        block = block - block.mean(axis=1, keepdims=True)  # remove per-packet gain changes
        values.append(float(block.std(axis=0).mean()))
    return float(np.mean(values)) if values else float("nan")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sessions", type=Path, default=ROOT / "dataset" / "v2_sessions")
    parser.add_argument("--out", type=Path, default=ROOT / "experiments" / "results" / "diagnostics" / "motion_signal.json")
    args = parser.parse_args()

    rows = read_metadata()
    stats = {width: np.full(len(rows), np.nan) for width in WIDTHS}
    loaded: dict[str, tuple] = {}
    for index, row in enumerate(rows):
        if row["recording"] not in loaded:
            loaded.clear()
            with np.load(args.sessions / f"{row['recording']}.npz") as data:
                iq = data["iq"][:, 0, 2:, :].astype(np.float32)  # first two LLTF values are masked
                loaded[row["recording"]] = (data["received_unix_ns"] / 1e9, data["node_id"],
                                            data["source_subcarriers"], np.log1p(np.hypot(iq[..., 0], iq[..., 1])))
        start = datetime.fromisoformat(row["ts_start_utc"].replace("Z", "+00:00")).timestamp()
        for width in WIDTHS:
            stats[width][index] = window_statistic(*loaded[row["recording"]], start, width)

    dynamic = np.array([0 if row["label"] in STATIC else 1 for row in rows])
    fall = np.array([row["is_fall"] for row in rows])
    report = {"statistic": "mean over subcarriers of temporal std of gain-removed log LLTF amplitude, 5 s window",
              "by_width": {}}
    for width in WIDTHS:
        values = stats[width]
        ok = ~np.isnan(values)
        groups = defaultdict(list)
        for row, value in zip(rows, values):
            if not np.isnan(value):
                groups[f"{row['date']} {row['label']}"].append(value)
        report["by_width"][width] = {
            "windows": int(ok.sum()),
            "auroc_dynamic_vs_static": round(auroc(dynamic[ok], values[ok]), 3),
            "auroc_fall_vs_rest": round(auroc(fall[ok], values[ok]), 3),
            "median_by_session_label": {key: round(float(np.median(v)), 4) for key, v in sorted(groups.items())},
        }
        print(f"width {width:>3}: dynamic-vs-static AUROC {report['by_width'][width]['auroc_dynamic_vs_static']}, "
              f"fall-vs-rest AUROC {report['by_width'][width]['auroc_fall_vs_rest']}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()

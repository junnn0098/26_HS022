"""Validate saved Hanium RuView CSI session files before model training."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

from .capture_labeled import SCHEMA_VERSION
from .labels import validate_label


REQUIRED_ARRAYS = (
    "meta_json",
    "iq",
    "received_unix_ns",
    "received_monotonic_ns",
    "node_id",
    "sequence",
    "rssi_dbm",
)


def validate_file(path: Path, min_pps: float, max_gap_rate: float) -> tuple[bool, dict]:
    errors: list[str] = []
    warnings: list[str] = []
    with np.load(path, allow_pickle=False) as data:
        missing = [name for name in REQUIRED_ARRAYS if name not in data]
        if missing:
            return False, {"file": str(path), "errors": [f"missing arrays: {missing}"]}

        try:
            meta = json.loads(str(data["meta_json"].item()))
        except Exception as exc:
            return False, {"file": str(path), "errors": [f"invalid metadata: {exc}"]}

        iq = data["iq"]
        timestamps = data["received_monotonic_ns"]
        nodes = data["node_id"]
        sequences = data["sequence"]
        rssis = data["rssi_dbm"]

        if meta.get("schema") != SCHEMA_VERSION:
            errors.append(f"schema={meta.get('schema')!r}, expected={SCHEMA_VERSION!r}")
        try:
            validate_label(str(meta.get("activity")), int(meta.get("people_actual")))
        except (TypeError, ValueError) as exc:
            errors.append(f"label: {exc}")

        if iq.ndim != 4 or iq.shape[-1] != 2:
            errors.append(f"iq shape must be (frames, antennas, subcarriers, 2), got {iq.shape}")
        if iq.dtype != np.int8:
            errors.append(f"iq dtype must be int8, got {iq.dtype}")

        frame_count = iq.shape[0] if iq.ndim else 0
        for name in REQUIRED_ARRAYS[2:]:
            if data[name].shape[0] != frame_count:
                errors.append(f"{name} length={data[name].shape[0]} != frames={frame_count}")

        if frame_count < 2:
            errors.append("fewer than two frames")
            duration = 0.0
        else:
            if np.any(np.diff(timestamps.astype(np.int64)) < 0):
                errors.append("receive timestamps are not monotonic")
            duration = float(meta.get("capture_elapsed_seconds", 0.0))
            if duration <= 0:
                duration = (int(timestamps[-1]) - int(timestamps[0])) / 1e9
            if duration < 10:
                errors.append(f"capture duration too short: {duration:.3f}s")

        expected_subcarriers = int(meta.get("expected_subcarriers", 0))
        if iq.ndim == 4 and iq.shape[2] != expected_subcarriers:
            errors.append(
                f"subcarriers={iq.shape[2]}, metadata expects={expected_subcarriers}"
            )

        counts = Counter(int(value) for value in nodes)
        expected_nodes = [int(value) for value in meta.get("expected_nodes", [])]
        pps_by_node = {
            node: count / max(duration, 1e-9) for node, count in sorted(counts.items())
        }
        for node in expected_nodes:
            if counts[node] == 0:
                errors.append(f"expected node {node} is absent")
            elif pps_by_node[node] < min_pps:
                errors.append(f"node {node} pps={pps_by_node[node]:.3f} < {min_pps}")

        gaps: defaultdict[int, int] = defaultdict(int)
        reordered: defaultdict[int, int] = defaultdict(int)
        previous: dict[int, int] = {}
        for node_raw, sequence_raw in zip(nodes, sequences):
            node = int(node_raw)
            current = int(sequence_raw)
            if node in previous:
                delta = (current - previous[node]) & 0xFFFFFFFF
                if delta == 0 or delta >= 0x80000000:
                    reordered[node] += 1
                elif delta > 1:
                    gaps[node] += delta - 1
            previous[node] = current

        gap_rate_by_node = {
            node: gaps[node] / max(counts[node] + gaps[node], 1)
            for node in sorted(counts)
        }
        for node, rate in gap_rate_by_node.items():
            if rate > max_gap_rate:
                errors.append(f"node {node} sequence gap rate={rate:.4f} > {max_gap_rate}")
        if any(reordered.values()):
            warnings.append(f"duplicates/reordered={dict(reordered)}")

        report = {
            "file": str(path),
            "activity": meta.get("activity"),
            "people_actual": meta.get("people_actual"),
            "people_bucket": meta.get("people_bucket"),
            "frames": frame_count,
            "iq_shape": list(iq.shape),
            "duration_seconds": round(duration, 3),
            "pps_by_node": {str(k): round(v, 3) for k, v in pps_by_node.items()},
            "mean_rssi_dbm": round(float(np.mean(rssis)), 3) if len(rssis) else None,
            "sequence_gaps": dict(gaps),
            "gap_rate_by_node": {str(k): round(v, 6) for k, v in gap_rate_by_node.items()},
            "warnings": warnings,
            "errors": errors,
        }
        return not errors, report


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate one or more CSI .npz captures")
    parser.add_argument("paths", type=Path, nargs="+")
    parser.add_argument("--min-pps", type=float, default=20.0)
    parser.add_argument("--max-gap-rate", type=float, default=0.05)
    args = parser.parse_args()

    all_ok = True
    for supplied in args.paths:
        paths = sorted(supplied.glob("*.npz")) if supplied.is_dir() else [supplied]
        if not paths:
            print(f"NO_CAPTURE_FILES path={supplied}", file=sys.stderr)
            all_ok = False
        for path in paths:
            try:
                ok, report = validate_file(path, args.min_pps, args.max_gap_rate)
            except Exception as exc:
                ok = False
                report = {"file": str(path), "errors": [f"unhandled validation error: {exc}"]}
            print(json.dumps(report, ensure_ascii=False, indent=2))
            print("VALIDATION=PASS" if ok else "VALIDATION=FAIL")
            all_ok &= ok
    return 0 if all_ok else 2


if __name__ == "__main__":
    raise SystemExit(main())


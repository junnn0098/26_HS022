"""Build a subject-disjoint manifest for cough/confounder classification."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from .build_manifest import assign_group_splits
from .config import FeatureConfig
from .health_labels import HEALTH_EVENT_LABELS, validate_health_label


def main() -> int:
    parser = argparse.ArgumentParser(description="Build cough-event training manifest")
    parser.add_argument("capture_dirs", nargs="+", type=Path)
    parser.add_argument("--output", type=Path, default=Path("manifests/cough_v1.json"))
    parser.add_argument("--seed", type=int, default=20260901)
    parser.add_argument("--allow-incomplete-splits", action="store_true")
    args = parser.parse_args()
    config = FeatureConfig(window_seconds=2.0)
    paths: list[Path] = []
    for directory in args.capture_dirs:
        paths.extend(directory.glob("*.npz"))
    sessions: list[dict] = []
    rejected: list[dict] = []
    for path in sorted(set(item.resolve() for item in paths)):
        try:
            with np.load(path, allow_pickle=False) as data:
                meta = json.loads(str(data["meta_json"].item()))
                shape = list(data["iq"].shape)
            if meta.get("schema") != "hanium.ruview.health-capture.v1":
                raise ValueError("not a health capture")
            validate_health_label(str(meta["label"]))
            if shape[2:] != [config.subcarriers, 2]:
                raise ValueError(f"unsupported IQ shape: {shape}")
            meta["path"] = str(path)
            sessions.append(meta)
        except Exception as exc:
            rejected.append({"path": str(path), "reason": str(exc)})
    if not sessions:
        parser.error("no valid health captures found")
    groups = ["subject@" + str(meta["subject"]) for meta in sessions]
    try:
        split_map = assign_group_splits(groups, args.seed)
    except ValueError:
        if not args.allow_incomplete_splits:
            raise
        split_map = {group: "train" for group in groups}
    samples = []
    for index, (meta, group) in enumerate(zip(sessions, groups)):
        duration = float(meta["capture_elapsed_seconds"])
        event_at = meta.get("event_offset_seconds")
        center = float(event_at) if event_at is not None else duration / 2.0
        start = min(max(0.0, center - config.window_seconds / 2.0), max(0.0, duration - config.window_seconds))
        label = str(meta["label"])
        samples.append(
            {
                "session_index": index,
                "path": meta["path"],
                "start_seconds": round(start, 6),
                "label": label,
                "label_index": HEALTH_EVENT_LABELS.index(label),
                "split_group": group,
                "split": split_map[group],
            }
        )
    payload = {
        "schema": "hanium.ruview.cough-manifest.v1",
        "feature_config": {
            "subcarriers": config.subcarriers,
            "sample_rate_hz": config.sample_rate_hz,
            "window_seconds": config.window_seconds,
            "window_frames": config.window_frames,
            "feature_channels": config.feature_channels,
            "max_nodes": config.max_nodes,
        },
        "labels": list(HEALTH_EVENT_LABELS),
        "seed": args.seed,
        "split_groups": split_map,
        "sessions": sessions,
        "samples": samples,
        "rejected": rejected,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    split_counts = {split: sum(item["split"] == split for item in samples) for split in ("train", "val", "test")}
    print(f"COUGH_MANIFEST={args.output.resolve()}")
    print(f"SESSIONS={len(sessions)} SAMPLES={len(samples)} SPLITS={split_counts} REJECTED={len(rejected)}")
    print("RESULT=PASS_COUGH_MANIFEST_BUILT")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


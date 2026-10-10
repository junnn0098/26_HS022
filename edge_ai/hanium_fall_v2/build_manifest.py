"""Build leakage-resistant train/validation/test window manifests."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np

from .config import FeatureConfig
from .labels import ACTIVITIES, people_bucket, validate_label


COUNT_LABELS = ("0", "1", "2", "3plus")
EVENT_ACTIVITIES = {"fall", "sit_down", "lie_down", "stand_up"}
MANIFEST_SCHEMA = "hanium.ruview.window-manifest.v1"


def stable_key(seed: int, value: str) -> str:
    return hashlib.sha256(f"{seed}:{value}".encode()).hexdigest()


def assign_group_splits(groups: list[str], seed: int) -> dict[str, str]:
    ordered = sorted(set(groups), key=lambda value: stable_key(seed, value))
    if len(ordered) < 3:
        raise ValueError(
            "at least three independent subject groups are required for train/val/test; "
            "use --allow-incomplete-splits only for a pipeline smoke test"
        )
    test_count = max(1, int(round(len(ordered) * 0.15)))
    val_count = max(1, int(round(len(ordered) * 0.15)))
    if test_count + val_count >= len(ordered):
        test_count = val_count = 1
    result: dict[str, str] = {}
    for index, group in enumerate(ordered):
        if index < test_count:
            result[group] = "test"
        elif index < test_count + val_count:
            result[group] = "val"
        else:
            result[group] = "train"
    return result


def connected_subject_groups(sessions: list[dict]) -> list[str | None]:
    """Keep every session containing an overlapping participant in one split."""
    parent: dict[str, str] = {}

    def find(value: str) -> str:
        parent.setdefault(value, value)
        while parent[value] != value:
            parent[value] = parent[parent[value]]
            value = parent[value]
        return value

    def union(left: str, right: str) -> None:
        left_root, right_root = find(left), find(right)
        if left_root != right_root:
            parent[right_root] = left_root

    participant_lists: list[list[str]] = []
    for meta in sessions:
        if meta["activity"] == "empty":
            participant_lists.append([])
            continue
        participants = [str(item) for item in meta.get("participants", []) if str(item)]
        if not participants:
            participants = [str(meta.get("subject", "unknown_subject"))]
        participant_lists.append(participants)
        for participant in participants:
            find(participant)
        for participant in participants[1:]:
            union(participants[0], participant)

    components: dict[str, set[str]] = {}
    for participant in parent:
        components.setdefault(find(participant), set()).add(participant)
    groups: list[str | None] = []
    for participants in participant_lists:
        if not participants:
            groups.append(None)
            continue
        members = sorted(components[find(participants[0])])
        groups.append("subjects@" + "+".join(members))
    return groups


def read_session(path: Path) -> dict:
    with np.load(path, allow_pickle=False) as data:
        meta = json.loads(str(data["meta_json"].item()))
        frame_count = int(data["iq"].shape[0])
        iq_shape = list(data["iq"].shape)
    validate_label(str(meta["activity"]), int(meta["people_actual"]))
    config = FeatureConfig()
    if iq_shape[2] != config.subcarriers or iq_shape[-1] != 2:
        raise ValueError(f"unsupported IQ shape: {iq_shape}")
    meta["path"] = str(path.resolve())
    meta["frame_count"] = frame_count
    meta["iq_shape"] = iq_shape
    return meta


def main() -> int:
    parser = argparse.ArgumentParser(description="Build subject-disjoint CSI window manifest")
    parser.add_argument("capture_dirs", nargs="+", type=Path)
    parser.add_argument("--output", type=Path, default=Path("manifests/dataset_v1.json"))
    parser.add_argument("--stride-seconds", type=float, default=1.0)
    parser.add_argument("--seed", type=int, default=20260828)
    parser.add_argument("--allow-incomplete-splits", action="store_true")
    args = parser.parse_args()

    config = FeatureConfig()
    paths: list[Path] = []
    for directory in args.capture_dirs:
        paths.extend(sorted(directory.glob("*.npz")))
    paths = sorted(set(path.resolve() for path in paths))
    if not paths:
        parser.error("no .npz captures found")

    sessions: list[dict] = []
    rejected: list[dict[str, str]] = []
    for path in paths:
        try:
            meta = read_session(path)
            activity = str(meta["activity"])
            if activity in EVENT_ACTIVITIES and "event_offset_seconds" not in meta:
                raise ValueError(f"event label {activity} requires capture_event metadata")
            sessions.append(meta)
        except Exception as exc:
            rejected.append({"path": str(path), "reason": str(exc)})

    if not sessions:
        print(json.dumps({"rejected": rejected}, indent=2, ensure_ascii=False))
        return 2

    subject_groups: list[str] = []
    empty_groups: list[str] = []
    connected_groups = connected_subject_groups(sessions)
    for meta, connected_group in zip(sessions, connected_groups):
        room = str(meta.get("room", "unknown_room"))
        if meta["activity"] == "empty":
            group = f"empty@{room}@{meta.get('session', Path(meta['path']).stem)}"
            empty_groups.append(group)
        else:
            if connected_group is None:
                raise ValueError("non-empty session has no participant group")
            group = connected_group
            subject_groups.append(group)
        meta["split_group"] = group

    try:
        split_map = assign_group_splits(subject_groups, args.seed)
    except ValueError:
        if not args.allow_incomplete_splits:
            raise
        split_map = {group: "train" for group in subject_groups}
    ordered_empty = sorted(set(empty_groups), key=lambda value: stable_key(args.seed, value))
    empty_cycle = ("train", "val", "test")
    for index, group in enumerate(ordered_empty):
        split_map[group] = empty_cycle[index % len(empty_cycle)]

    samples: list[dict] = []
    for session_index, meta in enumerate(sessions):
        duration = float(meta["capture_elapsed_seconds"])
        activity = str(meta["activity"])
        if activity in EVENT_ACTIVITIES:
            event_offset = float(meta["event_offset_seconds"])
            starts = [
                min(
                    max(0.0, event_offset - config.window_seconds / 2),
                    max(0.0, duration - config.window_seconds),
                )
            ]
        else:
            usable = max(0.0, duration - config.window_seconds)
            count = int(math.floor(usable / args.stride_seconds)) + 1
            starts = [index * args.stride_seconds for index in range(max(0, count))]

        pps_values = [float(value) for value in meta.get("pps_by_node", {}).values()]
        gap_values = [int(value) for value in meta.get("sequence_gaps", {}).values()]
        valid_frames = max(int(meta.get("valid_frames", meta["frame_count"])), 1)
        quality_target = min(1.0, min(pps_values, default=0.0) / config.sample_rate_hz)
        quality_target *= max(0.0, 1.0 - sum(gap_values) / valid_frames)

        for start in starts:
            samples.append(
                {
                    "session_index": session_index,
                    "path": meta["path"],
                    "start_seconds": round(float(start), 6),
                    "activity": activity,
                    "activity_index": ACTIVITIES.index(activity),
                    "people_bucket": people_bucket(int(meta["people_actual"])),
                    "count_index": COUNT_LABELS.index(people_bucket(int(meta["people_actual"]))),
                    "quality_target": round(float(quality_target), 6),
                    "split_group": meta["split_group"],
                    "split": split_map[meta["split_group"]],
                }
            )

    payload = {
        "schema": MANIFEST_SCHEMA,
        "feature_config": {
            "subcarriers": config.subcarriers,
            "sample_rate_hz": config.sample_rate_hz,
            "window_seconds": config.window_seconds,
            "window_frames": config.window_frames,
            "feature_channels": config.feature_channels,
            "max_nodes": config.max_nodes,
        },
        "activity_labels": list(ACTIVITIES),
        "count_labels": list(COUNT_LABELS),
        "seed": args.seed,
        "split_groups": split_map,
        "sessions": sessions,
        "samples": samples,
        "rejected": rejected,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    split_counts = {
        split: sum(sample["split"] == split for sample in samples)
        for split in ("train", "val", "test")
    }
    print(f"MANIFEST={args.output.resolve()}")
    print(f"SESSIONS={len(sessions)} SAMPLES={len(samples)} SPLITS={split_counts}")
    print(f"REJECTED={len(rejected)}")
    print("RESULT=PASS_MANIFEST_BUILT")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

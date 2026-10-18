"""원본 RuView 녹화(JSONL)를 v2 파이프라인의 세션 NPZ 형식으로 바꾼다.

RuView 녹화기는 ADR-018 UDP 패킷에서 앞 8바이트(magic, node_id, antennas, subcarriers)를
떼고 나머지를 iq_hex로 저장했다. node_id와 폭(subcarriers 필드 - 6)으로 앞부분을 다시
붙이면 원래 패킷이 되므로, v2의 엄격한 파서(hanium_fall_v2.adr018)를 그대로 통과시킬 수 있다.
결과 파일은 edge_ai/hanium_fall_v2/capture_labeled.py가 만드는 세션 NPZ와 같은 배열 이름을
쓰며, 첫 번째 LLTF 블록(64 서브캐리어)만 담는다.

  python dataset/tools/raw_to_v2.py --raw <recordings 폴더> --out <저장 폴더>
"""

from __future__ import annotations

import argparse
import csv
import json
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "edge_ai"))

from hanium_fall_v2.adr018 import (  # noqa: E402
    LTF_SELECTION_POLICY, MAGIC, extract_lltf_iq, parse_adr018, sequence_gap,
)

from labels import LABELS  # noqa: E402

SCHEMA = "hanium.ruview.csi.session.v1"
PREFIX = struct.Struct("<IBBH")

# 녹화 단위 라벨 -> v2 학습 라벨(hanium_fall_v2/labels.py). 여러 동작이 섞인 녹화는 other_motion.
V2_ACTIVITY = {
    "fall": "fall", "walking": "walking", "standing": "standing_still", "sitting": "sitting",
    "lying": "lying", "sit_down": "sit_down",
}


def rebuild_packet(record: dict) -> bytes:
    payload = bytes.fromhex(record["iq_hex"])
    return PREFIX.pack(MAGIC, int(record["node_id"]), 1, int(record["subcarriers"]) - 6) + payload


def convert(path: Path, meta_row: dict) -> tuple[dict, dict]:
    columns = defaultdict(list)
    width_counts, rejected = Counter(), Counter()
    last_sequence: dict[int, int] = {}
    gaps, valid_by_node = Counter(), Counter()
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("type") != "raw_csi":
                continue
            try:
                frame = parse_adr018(rebuild_packet(record))
                iq = extract_lltf_iq(frame)
            except ValueError as exc:
                rejected[str(exc).split(":")[0]] += 1
                continue
            node = frame.node_id
            if node in last_sequence:
                gap = sequence_gap(last_sequence[node], frame.sequence)
                gaps[node] += max(gap, 0)
            last_sequence[node] = frame.sequence
            valid_by_node[node] += 1
            width_counts[frame.subcarriers] += 1
            columns["iq"].append(iq)
            columns["received_unix_ns"].append(int(record["ts_ns"]))
            columns["node_id"].append(node)
            columns["sequence"].append(frame.sequence)
            columns["frequency_mhz"].append(frame.frequency_mhz)
            columns["rssi_dbm"].append(frame.rssi_dbm)
            columns["noise_floor_dbm"].append(frame.noise_floor_dbm)
            columns["ppdu"].append(frame.ppdu)
            columns["flags"].append(frame.flags)
            columns["source_subcarriers"].append(frame.subcarriers)

    stamps = np.asarray(columns["received_unix_ns"], dtype=np.int64)
    elapsed = float((stamps.max() - stamps.min()) / 1e9)
    label = meta_row["label"]
    meta = {
        "schema": SCHEMA,
        "source": "RuView recorder JSONL (ADR-018 payload without the 8-byte prefix), converted offline",
        "recording": meta_row["recording"],
        "activity": V2_ACTIVITY.get(label, "other_motion"),
        "recorded_label": label,
        "recorded_category": LABELS[label]["category"],
        "window_policy": "sliding" if label != "fall" else "repeated_events_recording_level_label",
        "people_actual": 1,
        "subject": meta_row["subject"],
        "participants": [meta_row["subject"]] if meta_row["subject"] != "unrecorded" else [],
        "session": meta_row["date"],
        "expected_nodes": [1, 2, 3, 4],
        "selected_ltf": "LLTF",
        "ltf_selection_policy": LTF_SELECTION_POLICY,
        "raw_subcarrier_counts": {str(k): v for k, v in sorted(width_counts.items())},
        "rejected_reasons": dict(rejected),
        "capture_elapsed_seconds": round(elapsed, 3),
        "valid_frames": int(len(stamps)),
        "valid_by_node": {str(k): v for k, v in sorted(valid_by_node.items())},
        "pps_by_node": {str(k): round(v / elapsed, 2) for k, v in sorted(valid_by_node.items())},
        "sequence_gaps": {str(k): v for k, v in sorted(gaps.items())},
    }
    arrays = {
        "iq": np.stack(columns["iq"]).astype(np.int8, copy=False),
        "received_unix_ns": stamps,
        "received_monotonic_ns": stamps,  # 녹화기는 벽시계 시각만 저장했다
        "node_id": np.asarray(columns["node_id"], dtype=np.uint8),
        "sequence": np.asarray(columns["sequence"], dtype=np.uint32),
        "frequency_mhz": np.asarray(columns["frequency_mhz"], dtype=np.uint32),
        "rssi_dbm": np.asarray(columns["rssi_dbm"], dtype=np.int8),
        "noise_floor_dbm": np.asarray(columns["noise_floor_dbm"], dtype=np.int8),
        "ppdu": np.asarray(columns["ppdu"], dtype=np.uint8),
        "flags": np.asarray(columns["flags"], dtype=np.uint8),
        "source_subcarriers": np.asarray(columns["source_subcarriers"], dtype=np.uint16),
    }
    return meta, arrays


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw", type=Path, required=True, help="csi-<epoch>.csi.jsonl 파일이 있는 폴더")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--recordings", type=Path,
                        default=Path(__file__).resolve().parents[1] / "metadata" / "recordings.csv")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    with args.recordings.open(encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    for row in rows:
        target = args.out / f"{row['recording']}.npz"
        meta, arrays = convert(args.raw / row["csi_file"], row)
        np.savez_compressed(target, meta_json=np.asarray(json.dumps(meta, ensure_ascii=False)), **arrays)
        print(f"{row['recording']}: {meta['valid_frames']} LLTF frames, "
              f"{meta['pps_by_node']} pps, rejected {sum(meta['rejected_reasons'].values())}, "
              f"{target.stat().st_size / 1e6:.1f} MB", flush=True)


if __name__ == "__main__":
    main()

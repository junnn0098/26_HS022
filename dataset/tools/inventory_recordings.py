"""라벨이 붙은 원본 녹화(CSI + 웹캠 관절 좌표)의 목록과 품질 통계를 만든다.

출력: dataset/metadata/recordings.csv (녹화 1건 = 1행)

사용 예
  python dataset/tools/inventory_recordings.py --ruview <RuView 폴더> --subject-map <비공개 대응표.csv>
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np

from labels import LABELS, anonymize

KST = timezone(timedelta(hours=9))

# (전체 녹화 라벨표, 학습 윈도우 배치 이름, 학습에 쓴 녹화만 남긴 라벨표 또는 None=전부 사용)
LABEL_TABLES = [
    ("labels.csv", "b1_0708_0709", None),
    ("labels_batch3.csv", "b2_0715", "labels_batch3_filtered.csv"),
    ("labels_3rd.csv", "b3_0724", None),
    ("labels_4th.csv", "b4_0728", None),
]
# 녹화 날짜 → 팀 내부 차수 이름
TEAM_ROUND = {"2026-07-08": "1차", "2026-07-09": "2차", "2026-07-15": "낙상 보강", "2026-07-24": "3차", "2026-07-28": "4차"}


def header_fields(iq_hex: str) -> tuple[int, int, int]:
    """iq_hex는 ADR-018 패킷의 오프셋 8(9번째 바이트, 주파수)부터다: 주파수(4) 순번(4) RSSI(1) 잡음 하한(1) ..."""
    raw = bytes.fromhex(iq_hex[:20])
    frequency = int.from_bytes(raw[0:4], "little")
    rssi = int.from_bytes(raw[8:9], "little", signed=True)
    noise = int.from_bytes(raw[9:10], "little", signed=True)
    return frequency, rssi, noise


def csi_stats(path: Path) -> dict:
    nodes, widths, rssi, noise, frequency = Counter(), Counter(), {}, [], Counter()
    first = last = None
    packets = 0
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("type") != "raw_csi":
                continue
            packets += 1
            node = int(record["node_id"])
            nodes[node] += 1
            widths[int(record["subcarriers"])] += 1
            # 레코드의 "rssi" 필드는 녹화기가 다른 바이트를 읽어 신뢰할 수 없어 헤더에서 직접 읽는다.
            mhz, packet_rssi, packet_noise = header_fields(record["iq_hex"])
            frequency[mhz] += 1
            rssi.setdefault(node, []).append(packet_rssi)
            noise.append(packet_noise)
            ts = int(record["ts_ns"])
            first = ts if first is None else first
            last = ts
    duration = (last - first) / 1e9 if packets > 1 else 0.0
    return {
        "csi_packets": packets,
        "duration_s": round(duration, 1),
        "packet_rate_hz": round(packets / duration, 1) if duration else 0.0,
        "nodes": " ".join(f"{n}:{c}" for n, c in sorted(nodes.items())),
        "modal_width": widths.most_common(1)[0][0] if widths else 0,
        "modal_width_share": round(widths.most_common(1)[0][1] / packets, 3) if packets else 0.0,
        "frequency_mhz": frequency.most_common(1)[0][0] if frequency else 0,
        "rssi_mean_dbm": " ".join(f"{n}:{np.mean(v):.0f}" for n, v in sorted(rssi.items())),
        "noise_floor_dbm": round(float(np.median(noise)), 1) if noise else 0.0,
        "start_kst": datetime.fromtimestamp(first / 1e9, KST).strftime("%Y-%m-%d %H:%M:%S") if first else "",
    }


def keypoint_stats(path: Path) -> dict:
    if not path.exists():
        return {"pose_frames": 0, "pose_fps": 0.0, "pose_confidence": 0.0}
    stamps, conf = [], []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                record = json.loads(line)
                stamps.append(int(record["ts_ns"]))
                conf.append(float(record.get("confidence", 0.0)))
    span = (stamps[-1] - stamps[0]) / 1e9 if len(stamps) > 1 else 0.0
    return {
        "pose_frames": len(stamps),
        "pose_fps": round(len(stamps) / span, 1) if span else 0.0,
        "pose_confidence": round(float(np.mean(conf)), 3) if conf else 0.0,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ruview", type=Path, required=True)
    parser.add_argument("--subject-map", type=Path)
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[1] / "metadata" / "recordings.csv")
    args = parser.parse_args()

    subjects: dict[str, str] = {}
    if args.subject_map:
        with args.subject_map.open(encoding="utf-8") as handle:
            subjects = {row["name"].strip(): row["subject_id"].strip() for row in csv.DictReader(handle)}

    rows = []
    for table, batch, used_table in LABEL_TABLES:
        with (args.ruview / table).open(encoding="utf-8") as handle:
            recordings = list(csv.DictReader(handle))
        used = None
        if used_table:
            with (args.ruview / used_table).open(encoding="utf-8") as handle:
                used = {row["csi_file"].strip() for row in csv.DictReader(handle)}
        for rec in recordings:
            csi_file = rec["csi_file"].strip()
            kp_file = rec["kp_file"].strip()
            label = rec["label"].strip()
            person = (rec.get("person") or "").strip()
            stats = csi_stats(args.ruview / "data" / "recordings" / csi_file)
            pose = keypoint_stats(args.ruview / "data" / "ground-truth" / kp_file)
            date = stats["start_kst"][:10]
            in_windows = used is None or csi_file in used
            rows.append({
                "recording": csi_file.replace(".csi.jsonl", ""),
                "csi_file": csi_file,
                "keypoints_file": kp_file,
                "date": date,
                "team_round": TEAM_ROUND.get(date, ""),
                "label": label,
                "label_ko": LABELS[label]["ko"],
                "category": LABELS[label]["category"],
                "subject": anonymize(person, subjects, f"{table} {csi_file}"),
                "window_batch": batch if in_windows else "",
                **stats,
                **pose,
            })
            print(f"{csi_file}: {label} {stats['duration_s']}s {stats['csi_packets']} pkts nodes[{stats['nodes']}]")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"{len(rows)} recordings -> {args.out}")


if __name__ == "__main__":
    main()

"""팀 학습 데이터(JSONL)를 출처가 붙은 NPZ 데이터셋으로 내보낸다.

입력 (RuView 작업 폴더, 공개 저장소에는 없음)
  data/for_ai_team/final_dataset_134ch*.jsonl   팀이 학습에 쓴 500프레임 x 134채널 윈도우
  data/paired/csi-<epoch>.paired.jsonl          align-ground-truth.js가 만든 20프레임 조각
  labels*.csv                                   녹화 파일 -> 동작 라벨(-> 참여자) 대응표

각 윈도우를 paired 조각 25개와 다시 맞춰 보고(값이 모두 같아야 통과) 어느 녹화의
몇 번째 구간인지 기록한다. 참여자 이름은 익명 ID로 바꾼다.

출력
  <out>/csi134_<batch>.npz   X: float32 (N, 500, 134), window_id: str (N,)
  dataset/metadata/windows.csv

사용 예
  python dataset/tools/export_windows.py --ruview <RuView 폴더> --out <저장 폴더>       --subject-map <비공개 참여자 대응표.csv>

참여자 대응표(name,subject_id)는 실명이 들어 있으므로 저장소에 올리지 않는다.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np

from labels import LABELS, anonymize

FRAMES = 500
CHANNELS = 134
ROWS_PER_WINDOW = 25  # paired 조각 1개 = 20프레임
KST = timezone(timedelta(hours=9))

# 팀이 실제로 학습 파일을 만들 때 사용한 (라벨표, 결과 파일) 조합
BATCHES = [
    ("b1_0708_0709", "labels.csv", "final_dataset_134ch.jsonl"),
    ("b2_0715", "labels_batch3_filtered.csv", "final_dataset_134ch_batch3_clean.jsonl"),
    ("b3_0724", "labels_3rd.csv", "final_dataset_134ch_batch3.jsonl"),
    ("b4_0728", "labels_4th.csv", "final_dataset_134ch_batch4.jsonl"),
]


def keep_full_channels(flat: list[float]) -> np.ndarray:
    """convert_for_ai_team_134ch_v3.py와 같은 규칙으로 20 x 134 조각을 만든다."""
    mat = np.asarray(flat, dtype=np.float32).reshape(20, -1)
    if mat.shape[1] >= CHANNELS:
        return mat[:, :CHANNELS]
    return np.pad(mat, ((0, 0), (0, CHANNELS - mat.shape[1])))


def paired_windows(path: Path):
    """paired 파일을 25조각씩 끊어 (윈도우, 메타데이터)를 순서대로 돌려준다."""
    with path.open(encoding="utf-8") as handle:
        rows = [json.loads(line) for line in handle if line.strip()]
    for start in range(0, len(rows) - ROWS_PER_WINDOW + 1, ROWS_PER_WINDOW):
        chunk = rows[start:start + ROWS_PER_WINDOW]
        window = np.concatenate([keep_full_channels(row["csi"]) for row in chunk])
        begin = datetime.fromisoformat(chunk[0]["ts_start"].replace("Z", "+00:00"))
        end = datetime.fromisoformat(chunk[-1]["ts_end"].replace("Z", "+00:00"))
        meta = {
            "chunk_index": start // ROWS_PER_WINDOW,
            "date": begin.astimezone(KST).strftime("%Y-%m-%d"),
            "ts_start_utc": chunk[0]["ts_start"],
            "ts_end_utc": chunk[-1]["ts_end"],
            "duration_s": round((end - begin).total_seconds(), 2),
            "source_width": int(chunk[0]["csi_shape"][1]),
            "camera_frames": sum(int(row.get("n_camera_frames", 0)) for row in chunk),
            "pose_confidence": round(float(np.mean([row.get("conf", 0.0) for row in chunk])), 4),
            "max_persons": max(int(row.get("n_persons_max", 1)) for row in chunk),
        }
        yield window, meta


def team_windows(path: Path):
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                record = json.loads(line)
                yield np.asarray(record["csi"], dtype=np.float32), record


def export_batch(ruview: Path, batch: str, labels_name: str, final_name: str, out_dir: Path,
                 subjects: dict[str, str]):
    with (ruview / labels_name).open(encoding="utf-8") as handle:
        recordings = list(csv.DictReader(handle))

    expected = []
    for rec in recordings:
        stem = rec["csi_file"].replace(".csi.jsonl", "")
        paired = ruview / "data" / "paired" / f"{stem}.paired.jsonl"
        for window, meta in paired_windows(paired):
            expected.append((window, rec, stem, meta))

    rows, arrays = [], []
    team = team_windows(ruview / "data" / "for_ai_team" / final_name)
    for index, ((window, rec, stem, meta), (team_window, team_record)) in enumerate(zip(expected, team, strict=True)):
        if team_window.shape != (FRAMES, CHANNELS) or not np.array_equal(window, team_window):
            raise SystemExit(f"{batch}: window {index} ({stem}) does not match the team file")
        if team_record["label"] != rec["label"].strip():
            raise SystemExit(f"{batch}: label mismatch at {index}")
        label = rec["label"].strip()
        person = (rec.get("person") or "").strip() or None
        window_id = f"{batch}_{index:04d}"
        arrays.append(team_window)
        rows.append({
            "window_id": window_id,
            "batch": batch,
            "npz_file": f"csi134_{batch}.npz",
            "npz_index": index,
            "recording": stem,
            "keypoints_file": rec["kp_file"].strip(),
            "label": label,
            "label_ko": LABELS[label]["ko"],
            "category": LABELS[label]["category"],
            "is_fall": int(label == "fall"),
            "subject": anonymize(person, subjects, f"{labels_name} {stem}"),
            **meta,
        })

    stacked = np.stack(arrays)
    out_path = out_dir / f"csi134_{batch}.npz"
    np.savez_compressed(out_path, X=stacked, window_id=np.array([r["window_id"] for r in rows]))
    digest = hashlib.sha256(out_path.read_bytes()).hexdigest()
    print(f"{batch}: {len(rows)} windows from {len(recordings)} recordings -> {out_path.name} "
          f"({out_path.stat().st_size / 1e6:.1f} MB, sha256 {digest[:12]})")
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ruview", type=Path, required=True, help="RuView 작업 폴더")
    parser.add_argument("--out", type=Path, required=True, help="NPZ를 저장할 폴더 (저장소 밖 권장)")
    parser.add_argument("--metadata", type=Path, default=Path(__file__).resolve().parents[1] / "metadata" / "windows.csv")
    parser.add_argument("--subject-map", type=Path, help="비공개 name,subject_id CSV")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    subjects: dict[str, str] = {}
    if args.subject_map:
        with args.subject_map.open(encoding="utf-8") as handle:
            subjects = {row["name"].strip(): row["subject_id"].strip() for row in csv.DictReader(handle)}

    rows = []
    for batch, labels_name, final_name in BATCHES:
        rows.extend(export_batch(args.ruview, batch, labels_name, final_name, args.out, subjects))

    args.metadata.parent.mkdir(parents=True, exist_ok=True)
    with args.metadata.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"metadata: {len(rows)} rows -> {args.metadata}")


if __name__ == "__main__":
    main()

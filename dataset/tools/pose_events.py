"""웹캠 관절 좌표로 각 윈도우 안에서 몸통이 얼마나 빠르게 내려갔는지 계산한다.

윈도우 라벨은 녹화 단위로 붙어 있다(낙상 녹화의 5초 구간은 모두 fall). 낙상 녹화에서는
넘어짐 -> 누워 있음 -> 일어남이 약 8초 주기로 반복되므로, 구간별 몸통 하강 정도를
함께 기록해 두면 이후 구간 단위 라벨을 만들거나 라벨 품질을 점검할 때 쓸 수 있다.
카메라 위치에 따라 값의 크기가 달라지므로 단독 낙상 판정 기준으로 쓰지 않는다.

몸통 높이 = 어깨(5, 6)와 엉덩이(11, 12) 관절 y 좌표의 평균 (0=화면 위, 1=화면 아래)
pose_frames       윈도우 안에서 몸통 관절이 모두 검출된 웹캠 프레임 수
pose_max_drop_1s  1초 이내에 몸통이 내려간 최대 거리 (화면 높이 비율)

  python dataset/tools/pose_events.py --ruview <RuView 폴더>   # windows.csv에 열을 추가
"""

from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime
from pathlib import Path

import numpy as np

METADATA = Path(__file__).resolve().parents[1] / "metadata" / "windows.csv"
TORSO = (5, 6, 11, 12)
DROP_SECONDS = 1.0


def load_torso(path: Path) -> tuple[np.ndarray, np.ndarray]:
    stamps, heights = [], []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            record = json.loads(line)
            points = record.get("keypoints") or []
            if len(points) < 13:
                continue
            torso = np.array([points[i] for i in TORSO], dtype=np.float64)
            if np.any(torso <= 0):  # 검출되지 않은 관절
                continue
            stamps.append(record["ts_ns"] / 1e9)
            heights.append(torso[:, 1].mean())
    return np.array(stamps), np.array(heights)


def max_drop(stamps: np.ndarray, heights: np.ndarray) -> float:
    best, j = 0.0, 0
    for i in range(len(stamps)):
        while stamps[j] < stamps[i] - DROP_SECONDS:
            j += 1
        best = max(best, heights[i] - heights[j:i + 1].min())
    return best


def seconds(stamp: str) -> float:
    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ruview", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, default=METADATA)
    args = parser.parse_args()

    with args.metadata.open(encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    cache: dict[str, tuple[np.ndarray, np.ndarray]] = {}
    for row in rows:
        name = row["keypoints_file"]
        if name not in cache:
            cache[name] = load_torso(args.ruview / "data" / "ground-truth" / name)
        stamps, heights = cache[name]
        inside = (stamps >= seconds(row["ts_start_utc"])) & (stamps <= seconds(row["ts_end_utc"]))
        drop = max_drop(stamps[inside], heights[inside]) if inside.sum() > 1 else 0.0
        row["pose_frames"] = int(inside.sum())
        row["pose_max_drop_1s"] = round(drop, 3)
        row.pop("pose_fall_onset", None)

    with args.metadata.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    print(f"{'label':16s} {'windows':>7s} {'median':>7s} {'p90':>6s}")
    for label in sorted({row["label"] for row in rows}):
        drops = np.array([row["pose_max_drop_1s"] for row in rows if row["label"] == label])
        print(f"{label:16s} {len(drops):7d} {np.median(drops):7.2f} {np.percentile(drops, 90):6.2f}")


if __name__ == "__main__":
    main()

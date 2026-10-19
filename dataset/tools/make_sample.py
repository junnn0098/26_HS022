"""저장소에 바로 들어가는 작은 샘플을 만든다 (전체 데이터는 Release에서 내려받음).

  sample/csi134_sample.npz    라벨마다 윈도우 1개 (X: float32 (15, 500, 134), window_id)
  sample/sample_windows.csv   위 윈도우의 메타데이터 (windows.csv와 같은 열, npz_file/npz_index는 샘플 기준)
  sample/raw/                 낙상 녹화 1건에서 2초 분량의 원본 CSI와 같은 시간대의 관절 좌표,
                              실시간 추론 재생 시연용 낙상 녹화 12초 (.csi.jsonl.gz)

  python dataset/tools/make_sample.py --ruview <RuView 폴더>
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
from datetime import datetime
from pathlib import Path

import numpy as np

DATASET = Path(__file__).resolve().parents[1]
RAW_WINDOW = "b4_0728_0300"
RAW_SECONDS = 2.0
REPLAY_RECORDING = "csi-1783443615"  # fall recording with 134-wide packets
REPLAY_SECONDS = (60.0, 72.0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ruview", type=Path, required=True)
    parser.add_argument("--data", type=Path, default=DATASET / "data")
    args = parser.parse_args()

    with (DATASET / "metadata" / "windows.csv").open(encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    picked = {}
    for row in rows:  # 라벨마다 녹화 중간쯤(chunk 20)의 윈도우 하나
        if row["label"] not in picked and int(row["chunk_index"]) == 20:
            picked[row["label"]] = row
    chosen = sorted(picked.values(), key=lambda row: (row["category"], row["label"]))

    arrays = []
    for row in chosen:
        with np.load(args.data / row["npz_file"]) as archive:
            arrays.append(archive["X"][int(row["npz_index"])])
    out = DATASET / "sample"
    (out / "raw").mkdir(parents=True, exist_ok=True)
    np.savez_compressed(out / "csi134_sample.npz", X=np.stack(arrays),
                        window_id=np.array([row["window_id"] for row in chosen]))
    with (out / "sample_windows.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(chosen[0]))
        writer.writeheader()
        # 샘플 NPZ를 그대로 load_windows()로 읽을 수 있게 파일 이름과 순번을 바꿔 적는다
        writer.writerows({**row, "npz_file": "csi134_sample.npz", "npz_index": i} for i, row in enumerate(chosen))

    window = next(row for row in rows if row["window_id"] == RAW_WINDOW)
    start = datetime.fromisoformat(window["ts_start_utc"].replace("Z", "+00:00")).timestamp() * 1e9
    end = start + RAW_SECONDS * 1e9
    for folder, name, suffix in (("recordings", f"{window['recording']}.csi.jsonl", ".excerpt.csi.jsonl"),
                                 ("ground-truth", window["keypoints_file"], ".excerpt.jsonl")):
        lines = []
        with (args.ruview / "data" / folder / name).open(encoding="utf-8") as handle:
            for line in handle:
                if line.strip() and start <= json.loads(line)["ts_ns"] < end:
                    lines.append(line)
        stem = name.split(".")[0]
        (out / "raw" / f"{stem}{suffix}").write_text("".join(lines), encoding="utf-8")
        print(f"{folder}: {len(lines)} lines")
    lines, first = [], None
    with (args.ruview / "data" / "recordings" / f"{REPLAY_RECORDING}.csi.jsonl").open(encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            stamp = json.loads(line)["ts_ns"] / 1e9
            first = stamp if first is None else first
            if REPLAY_SECONDS[0] <= stamp - first < REPLAY_SECONDS[1]:
                lines.append(line)
            elif stamp - first >= REPLAY_SECONDS[1]:
                break
    with gzip.open(out / "raw" / f"{REPLAY_RECORDING}.fall-12s.csi.jsonl.gz", "wt", encoding="utf-8") as handle:
        handle.write("".join(lines))
    print(f"replay excerpt: {len(lines)} packets")
    print(f"{len(chosen)} sample windows -> {out}")


if __name__ == "__main__":
    main()

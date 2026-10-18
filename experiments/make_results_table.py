"""Print the measured-data result table (markdown) from experiments/results/*.

  python experiments/make_results_table.py
"""

from __future__ import annotations

import json
from pathlib import Path

RESULTS = Path(__file__).resolve().parent / "results"

RUNS = [
    ("v1", "보고서 방식: 07-08·07-09 1,019개, 윈도우 무작위 80/20", "v1/report_1019_random_all", "5회"),
    ("v1", "2,217개 전체, 윈도우 무작위 80/20", "v1/random_all", "5회"),
    ("v1", "같은 분할, CSI가 아닌 헤더 5채널만 입력", "v1/random_non_csi", "5회"),
    ("v1", "1,019개, 녹화 단위 5겹", "v1/report_1019_recording_all", "5겹"),
    ("v1", "2,217개, 녹화 단위 5겹", "v1/recording_all", "5겹"),
    ("v1", "2,217개, 녹화 단위 5겹, LLTF 64채널만", "v1/recording_lltf", "5겹"),
    ("v1", "날짜 분할 (07-08~07-15 학습 → 07-24·07-28 시험)", "v1/temporal_all", "3회"),
    ("v1", "날짜 분할, 헤더 제외", "v1/temporal_csi", "3회"),
    ("v1", "날짜 분할, LLTF 64채널만", "v1/temporal_lltf", "3회"),
    ("v2", "2,217개, 녹화 단위 5겹", "v2_measured/recording", "5겹"),
    ("v2", "날짜 분할", "v2_measured/temporal", "3회"),
    ("v2", "녹화 단위 5겹, 192폭 패킷만", "v2_measured/recording_w192", "5겹"),
    ("v2", "날짜 분할, 192폭 패킷만", "v2_measured/temporal_w192", "3회"),
]


def fmt(stat: dict | None) -> str:
    if not stat:
        return "-"
    return f"{stat['mean']:.3f}" if stat["std"] < 0.0005 else f"{stat['mean']:.3f} ± {stat['std']:.3f}"


def main() -> None:
    print("| 모델 | 평가 방식 | 반복 | 낙상 재현율 | 정밀도 | AUROC | 낙상 검출 / 전체 | 오경보 |")
    print("|---|---|---|---:|---:|---:|---:|---:|")
    for model, name, path, repeats in RUNS:
        summary_path = RESULTS / path / "summary.json"
        if not summary_path.exists():
            print(f"| {model} | {name} | {repeats} | (실행 전) | | | | |")
            continue
        s = json.loads(summary_path.read_text(encoding="utf-8"))["summary"]
        print(f"| {model} | {name} | {repeats} | {fmt(s.get('recall'))} | {fmt(s.get('precision'))} | "
              f"{fmt(s.get('auroc'))} | {s['tp']} / {s['tp'] + s['fn']} | {s['fp']} |")
    for name in ("team_v1_0717", "team_v1_0803"):
        report = json.loads((RESULTS / "v1" / f"{name}.json").read_text(encoding="utf-8"))
        for batch, m in report["by_batch"].items():
            print(f"| 팀 가중치 `{name}` | {batch} 전체에 적용 | - | {m['recall']:.3f} | "
                  f"{'-' if m['precision'] is None else format(m['precision'], '.3f')} | {m['auroc']:.3f} | "
                  f"{m['tp']} / {m['tp'] + m['fn']} | {m['fp']} |")


if __name__ == "__main__":
    main()

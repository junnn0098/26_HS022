"""Draw the dataset and result figures used in README / dataset card / results report.

  python experiments/plot_figures.py
"""

from __future__ import annotations

import csv
import json
from collections import Counter
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]

SURFACE, INK, INK_2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
CATEGORY = {"daily": ("일상 동작", "#2a78d6"), "confusing": ("혼동 동작", "#1baf7a"), "fall": ("낙상", "#eb6834")}
BATCH_NAME = {"b1_0708_0709": "07-08·07-09\n(1·2차)", "b2_0715": "07-15\n(낙상 보강)",
              "b3_0724": "07-24\n(3차)", "b4_0728": "07-28\n(4차)"}

plt.rcParams.update({
    "font.family": "Malgun Gothic", "axes.unicode_minus": False, "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE, "axes.edgecolor": GRID, "axes.labelcolor": INK_2, "xtick.color": INK_2,
    "ytick.color": INK_2, "text.color": INK, "font.size": 10, "savefig.dpi": 160, "savefig.bbox": "tight",
})


def windows() -> list[dict]:
    with (ROOT / "dataset" / "metadata" / "windows.csv").open(encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def composition(rows: list[dict], out: Path) -> None:
    counts = Counter((row["batch"], row["category"]) for row in rows)
    batches = list(BATCH_NAME)
    fig, ax = plt.subplots(figsize=(7.2, 2.9))
    left = np.zeros(len(batches))
    for key, (name, color) in CATEGORY.items():
        values = np.array([counts[(batch, key)] for batch in batches])
        ax.barh(range(len(batches)), values, left=left, color=color, edgecolor=SURFACE, linewidth=2,
                height=0.62, label=name)
        for i, value in enumerate(values):
            if value >= 60:
                ax.text(left[i] + value / 2, i, f"{value}", ha="center", va="center", color="white", fontsize=9)
        left += values
    for i, total in enumerate(left):
        ax.text(total + 12, i, f"{int(total)}개", va="center", color=INK_2, fontsize=9)
    ax.set_yticks(range(len(batches)), [BATCH_NAME[b] for b in batches])
    ax.invert_yaxis()
    ax.set_xlim(0, left.max() * 1.12)
    ax.set_xlabel("5초 윈도우 수")
    ax.grid(axis="x", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.legend(ncols=3, frameon=False, loc="lower center", bbox_to_anchor=(0.45, 1.0))
    ax.set_title("수집일별 학습 윈도우 구성 (총 2,217개, 낙상 969개)", loc="left", fontsize=11, pad=24)
    fig.savefig(out)
    plt.close(fig)


def protocol_comparison(out: Path) -> None:
    results = ROOT / "experiments" / "results"

    def summary(path: str) -> dict:
        return json.loads((results / path / "summary.json").read_text(encoding="utf-8"))["summary"]

    team = json.loads((results / "v1" / "team_v1_0717.json").read_text(encoding="utf-8"))
    later = {key: sum(team["by_batch"][b][key] for b in ("b3_0724", "b4_0728")) for key in ("tp", "fn")}
    rows = [
        ("v1\n윈도우 무작위 분할", summary("v1/random_all")),
        ("v1\n헤더 5채널만 입력\n(누수 점검)", summary("v1/random_non_csi")),
        ("v1\n녹화 단위 분할", summary("v1/recording_all")),
        ("v1\n날짜 분할", summary("v1/temporal_all")),
        ("v2\n녹화 단위 분할", summary("v2_measured/recording")),
        ("v2\n날짜 분할", summary("v2_measured/temporal")),
    ]
    names = [name for name, _ in rows] + ["팀 가중치(07-17)\n이후 수집일에 적용"]
    recall = [m["recall"]["mean"] for _, m in rows] + [later["tp"] / (later["tp"] + later["fn"])]
    auroc = [m["auroc"]["mean"] for _, m in rows] + [
        float(np.mean([team["by_batch"][b]["auroc"] for b in ("b3_0724", "b4_0728")]))]
    x = np.arange(len(names))
    fig, ax = plt.subplots(figsize=(11, 4.0))
    ax.bar(x - 0.19, recall, width=0.36, color="#2a78d6", label="낙상 재현율 (임계값 0.5)", edgecolor=SURFACE, linewidth=2)
    ax.bar(x + 0.19, auroc, width=0.36, color="#eb6834", label="AUROC", edgecolor=SURFACE, linewidth=2)
    for i in range(len(names)):
        ax.text(x[i] - 0.19, recall[i] + 0.02, f"{recall[i]:.2f}", ha="center", fontsize=8, color=INK_2)
        ax.text(x[i] + 0.19, auroc[i] + 0.02, f"{auroc[i]:.2f}", ha="center", fontsize=8, color=INK_2)
    ax.axhline(0.5, color=INK_2, linestyle=(0, (4, 3)), linewidth=1, label="무작위 추측 수준 (AUROC 0.5)")
    ax.axvspan(-0.5, 1.5, color="#f0efec", zorder=-1)
    ax.text(0.5, 1.09, "같은 녹화가 학습·시험에 함께 들어감", ha="center", fontsize=8, color=INK_2)
    ax.text(4.0, 1.09, "처음 보는 녹화·날짜로 시험", ha="center", fontsize=8, color=INK_2)
    ax.set_xticks(x, names, fontsize=8.5, linespacing=1.3)
    ax.set_ylim(0, 1.15)
    ax.set_yticks([0, 0.25, 0.5, 0.75, 1.0])
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    ax.legend(frameon=False, ncols=3, loc="lower left", bbox_to_anchor=(0.0, 1.07), fontsize=9)
    ax.set_title("평가 방식별 낙상 감지 성능 (실측 2,217개 윈도우)", loc="left", fontsize=11, pad=40)
    fig.savefig(out)
    plt.close(fig)


def main() -> None:
    rows = windows()
    figures = ROOT / "dataset" / "figures"
    figures.mkdir(parents=True, exist_ok=True)
    composition(rows, figures / "composition.png")
    if (ROOT / "experiments" / "results" / "v2_measured" / "temporal" / "summary.json").exists():
        target = ROOT / "experiments" / "results" / "figures"
        target.mkdir(parents=True, exist_ok=True)
        protocol_comparison(target / "protocol_comparison.png")
    print("figures written")


if __name__ == "__main__":
    main()

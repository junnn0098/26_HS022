"""Draw the dataset composition figure and the v1 measured-result figure.

  python experiments/plot_figures.py
"""

from __future__ import annotations

import argparse
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
CATEGORY_ORDER = ("fall", "confusing", "daily")

KOREAN_FONTS = ["Malgun Gothic", "AppleGothic", "NanumGothic", "Noto Sans CJK KR", "Noto Sans KR"]
_installed = {font.name for font in matplotlib.font_manager.fontManager.ttflist}
if not _installed.intersection(KOREAN_FONTS):
    print("warning: no Korean font found; install Noto Sans CJK KR or NanumGothic for readable labels")

plt.rcParams.update({
    "font.family": "sans-serif", "font.sans-serif": KOREAN_FONTS + ["DejaVu Sans"], "axes.unicode_minus": False, "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE, "axes.edgecolor": GRID, "axes.labelcolor": INK_2, "xtick.color": INK_2,
    "ytick.color": INK_2, "text.color": INK, "font.size": 10, "savefig.dpi": 160, "savefig.bbox": "tight",
})


def windows() -> list[dict]:
    with (ROOT / "dataset" / "metadata" / "windows.csv").open(encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def composition(rows: list[dict], out: Path) -> None:
    """Window count per action (label_ko), coloured by category, sorted by category then count."""
    counts = Counter((row["category"], row["label_ko"]) for row in rows)
    actions = sorted(counts, key=lambda key: (CATEGORY_ORDER.index(key[0]), -counts[key], key[1]))
    # a half-row gap between category groups
    y, positions = 0.0, []
    for i, (category, _) in enumerate(actions):
        if i and category != actions[i - 1][0]:
            y += 0.5
        positions.append(y)
        y += 1
    values = np.array([counts[key] for key in actions])
    fig, ax = plt.subplots(figsize=(7.2, 5.4))
    for key in CATEGORY_ORDER:
        name, color = CATEGORY[key]
        index = [i for i, (category, _) in enumerate(actions) if category == key]
        ax.barh([positions[i] for i in index], values[index], color=color, edgecolor=SURFACE, linewidth=2,
                height=0.72, label=name)
    for pos, value in zip(positions, values):
        ax.text(value + 10, pos, f"{value:,}", va="center", color=INK_2, fontsize=9)
    ax.set_yticks(positions, [label for _, label in actions])
    ax.invert_yaxis()
    ax.set_xlim(0, values.max() * 1.1)
    ax.set_xlabel("5초 윈도우 수")
    ax.grid(axis="x", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.tick_params(axis="y", length=0)
    ax.legend(ncols=3, frameon=False, loc="lower left", bbox_to_anchor=(0.0, 1.0))
    falls = sum(row["is_fall"] == "1" for row in rows)
    ax.set_title(f"동작별 학습 윈도우 구성 (총 {len(rows):,}개, 낙상 {falls:,}개)", loc="left", fontsize=11, pad=24)
    fig.savefig(out)
    plt.close(fig)


V1_RUNS = [("b1_random", "기본 동작 세트 (11종) 1,019개", "#2a78d6"),
           ("random_all", "전체 동작 세트 (15종) 2,217개", "#eb6834")]
V1_METRICS = [("recall", "낙상 재현율"), ("precision", "정밀도"), ("f1", "F1"), ("auroc", "AUROC")]


def v1_results(out: Path) -> None:
    results = ROOT / "experiments" / "results" / "v1"
    x = np.arange(len(V1_METRICS))
    width = 0.36
    fig, ax = plt.subplots(figsize=(7.2, 3.6))
    for i, (name, title, color) in enumerate(V1_RUNS):
        summary = json.loads((results / name / "summary.json").read_text(encoding="utf-8"))["summary"]
        mean = np.array([summary[key]["mean"] for key, _ in V1_METRICS])
        std = np.array([summary[key]["std"] for key, _ in V1_METRICS])
        offset = (i - 0.5) * (width + 0.02)
        ax.bar(x + offset, mean, width=width, color=color, label=title, edgecolor=SURFACE, linewidth=2)
        ax.errorbar(x + offset, mean, yerr=std, fmt="none", ecolor=INK_2, elinewidth=1, capsize=3)
        for j in range(len(x)):
            ax.text(x[j] + offset, mean[j] + std[j] + 0.015, f"{mean[j]:.3f}", ha="center", va="bottom",
                    fontsize=8.5, color=INK_2)
    ax.set_xticks(x, [label for _, label in V1_METRICS])
    ax.set_ylim(0, 1.12)
    ax.set_yticks([0, 0.25, 0.5, 0.75, 1.0])
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.tick_params(axis="y", length=0)
    ax.legend(ncols=2, frameon=False, loc="lower left", bbox_to_anchor=(0.0, 1.0), fontsize=9)
    ax.text(0, 1.115, "윈도우 무작위 80/20 분할 · 시드 5회 평균 ± 표준편차 · 낙상 판정 임계값 0.5",
            transform=ax.transAxes, fontsize=9, color=INK_2)
    ax.set_title("v1 1D-CNN 낙상 감지 성능", loc="left", fontsize=11, pad=36)
    fig.savefig(out)
    plt.close(fig)


def main() -> None:
    argparse.ArgumentParser(description=__doc__).parse_args()
    rows = windows()
    figures = ROOT / "dataset" / "figures"
    figures.mkdir(parents=True, exist_ok=True)
    composition(rows, figures / "composition.png")
    target = ROOT / "experiments" / "results" / "figures"
    target.mkdir(parents=True, exist_ok=True)
    v1_results(target / "v1_results.png")
    print("figures written")


if __name__ == "__main__":
    main()

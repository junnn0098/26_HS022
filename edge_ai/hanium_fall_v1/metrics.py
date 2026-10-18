"""Fall-detection metrics (fall = positive class)."""

from __future__ import annotations

from collections import defaultdict

import numpy as np


def auroc(y_true: np.ndarray, score: np.ndarray) -> float | None:
    """Rank-based ROC AUC (ties averaged); None when only one class is present."""
    y = np.asarray(y_true).astype(bool)
    positives, negatives = int(y.sum()), int((~y).sum())
    if positives == 0 or negatives == 0:
        return None
    order = np.argsort(score, kind="mergesort")
    ranks = np.empty(len(score), dtype=np.float64)
    sorted_scores = np.asarray(score)[order]
    i = 0
    while i < len(sorted_scores):
        j = i
        while j + 1 < len(sorted_scores) and sorted_scores[j + 1] == sorted_scores[i]:
            j += 1
        ranks[order[i:j + 1]] = (i + j) / 2.0 + 1.0
        i = j + 1
    return float((ranks[y].sum() - positives * (positives + 1) / 2.0) / (positives * negatives))


def binary_metrics(y_true: np.ndarray, p_fall: np.ndarray, threshold: float = 0.5) -> dict:
    y = np.asarray(y_true).astype(int)
    pred = (np.asarray(p_fall) >= threshold).astype(int)
    tp = int(((pred == 1) & (y == 1)).sum())
    fp = int(((pred == 1) & (y == 0)).sum())
    tn = int(((pred == 0) & (y == 0)).sum())
    fn = int(((pred == 0) & (y == 1)).sum())

    def ratio(a: int, b: int) -> float | None:
        return round(a / b, 4) if b else None

    recall, precision = ratio(tp, tp + fn), ratio(tp, tp + fp)
    f1 = round(2 * precision * recall / (precision + recall), 4) if recall and precision else 0.0
    area = auroc(y, np.asarray(p_fall))
    return {
        "n": int(len(y)), "falls": int(y.sum()), "threshold": threshold,
        "tp": tp, "fp": fp, "tn": tn, "fn": fn,
        "recall": recall, "precision": precision, "f1": f1,
        "specificity": ratio(tn, tn + fp), "accuracy": ratio(tp + tn, len(y)),
        "auroc": None if area is None else round(area, 4),
    }


def per_label(rows: list[dict], p_fall: np.ndarray, threshold: float = 0.5) -> dict:
    """Share of windows predicted as fall for every recorded activity label."""
    groups: dict[str, list[float]] = defaultdict(list)
    category: dict[str, str] = {}
    for row, probability in zip(rows, p_fall):
        groups[row["label"]].append(float(probability))
        category[row["label"]] = row["category"]
    report = {}
    for label, values in sorted(groups.items(), key=lambda item: (category[item[0]], item[0])):
        values = np.asarray(values)
        flagged = int((values >= threshold).sum())
        report[label] = {
            "category": category[label], "n": int(len(values)),
            "predicted_fall": flagged, "predicted_fall_rate": round(flagged / len(values), 4),
        }
    return report


def summarize(runs: list[dict], keys=("recall", "precision", "f1", "specificity", "accuracy", "auroc")) -> dict:
    """Mean and standard deviation over folds/seeds."""
    summary = {}
    for key in keys:
        values = [run[key] for run in runs if run.get(key) is not None]
        if values:
            summary[key] = {"mean": round(float(np.mean(values)), 4), "std": round(float(np.std(values)), 4),
                            "min": round(float(np.min(values)), 4), "max": round(float(np.max(values)), 4)}
        summary.setdefault("runs_with_value", {})[key] = len(values)
    for key in ("tp", "fp", "tn", "fn"):
        if all(key in run for run in runs):
            summary[key] = int(sum(run[key] for run in runs))
    return summary

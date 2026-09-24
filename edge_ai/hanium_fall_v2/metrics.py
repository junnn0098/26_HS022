"""Dependency-free classification metrics."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np


def confusion_matrix(targets: np.ndarray, predictions: np.ndarray, classes: int) -> np.ndarray:
    matrix = np.zeros((classes, classes), dtype=np.int64)
    for target, prediction in zip(targets.astype(int), predictions.astype(int)):
        if 0 <= target < classes and 0 <= prediction < classes:
            matrix[target, prediction] += 1
    return matrix


def classification_report(
    targets: np.ndarray,
    predictions: np.ndarray,
    labels: list[str] | tuple[str, ...],
) -> dict:
    matrix = confusion_matrix(targets, predictions, len(labels))
    per_class: dict[str, dict[str, float | int]] = {}
    f1_values: list[float] = []
    for index, label in enumerate(labels):
        true_positive = int(matrix[index, index])
        false_positive = int(matrix[:, index].sum() - true_positive)
        false_negative = int(matrix[index, :].sum() - true_positive)
        support = int(matrix[index, :].sum())
        precision = true_positive / max(true_positive + false_positive, 1)
        recall = true_positive / max(true_positive + false_negative, 1)
        f1 = 2 * precision * recall / max(precision + recall, 1e-12)
        if support:
            f1_values.append(f1)
        per_class[label] = {
            "precision": round(precision, 6),
            "recall": round(recall, 6),
            "f1": round(f1, 6),
            "support": support,
        }
    accuracy = float(np.trace(matrix) / max(matrix.sum(), 1))
    return {
        "accuracy": round(accuracy, 6),
        "macro_f1": round(float(np.mean(f1_values)) if f1_values else 0.0, 6),
        "per_class": per_class,
        "confusion_matrix": matrix.tolist(),
    }


def save_report(report: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


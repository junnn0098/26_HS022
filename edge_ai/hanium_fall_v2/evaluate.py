"""Evaluate a checkpoint on a held-out manifest split."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from .dataset import CsiWindowDataset
from .labels import DISPLAY_ACTIVITIES, display_activity
from .metrics import classification_report, save_report


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate Hanium RuView checkpoint")
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--split", choices=("train", "val", "test"), default="test")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--output", type=Path, default=Path("reports/test_metrics.json"))
    parser.add_argument("--device", default="auto")
    args = parser.parse_args()

    import torch
    from torch.utils.data import DataLoader

    from .fall_checkpoint import require_live_ready_fall_checkpoint
    from .model import model_from_checkpoint

    device = torch.device(
        "cuda" if args.device == "auto" and torch.cuda.is_available() else
        "cpu" if args.device == "auto" else args.device
    )
    checkpoint = torch.load(args.checkpoint, map_location=device, weights_only=False)
    require_live_ready_fall_checkpoint(checkpoint, torch)
    model = model_from_checkpoint(checkpoint, device)
    dataset = CsiWindowDataset(args.manifest, args.split, augment=False)
    loader = DataLoader(dataset, batch_size=args.batch_size, shuffle=False, num_workers=args.workers)
    activity_targets: list[int] = []
    activity_predictions: list[int] = []
    count_targets: list[int] = []
    count_predictions: list[int] = []
    quality_values: list[float] = []
    with torch.no_grad():
        for batch in loader:
            outputs = model(
                batch["features"].to(device),
                batch["node_mask"].to(device),
                batch["node_quality"].to(device),
            )
            activity_targets.extend(batch["activity"].tolist())
            activity_predictions.extend(outputs["activity_logits"].argmax(1).cpu().tolist())
            count_targets.extend(batch["count"].tolist())
            count_predictions.extend(outputs["count_logits"].argmax(1).cpu().tolist())
            quality_values.extend(outputs["quality"].cpu().tolist())
    report = {
        "checkpoint": str(args.checkpoint.resolve()),
        "manifest": str(args.manifest.resolve()),
        "split": args.split,
        "samples": len(dataset),
        "activity": classification_report(
            np.asarray(activity_targets),
            np.asarray(activity_predictions),
            checkpoint["activity_labels"],
        ),
        "display_activity": classification_report(
            np.asarray(
                [
                    DISPLAY_ACTIVITIES.index(display_activity(checkpoint["activity_labels"][index]))
                    for index in activity_targets
                ]
            ),
            np.asarray(
                [
                    DISPLAY_ACTIVITIES.index(display_activity(checkpoint["activity_labels"][index]))
                    for index in activity_predictions
                ]
            ),
            DISPLAY_ACTIVITIES,
        ),
        "count": classification_report(
            np.asarray(count_targets),
            np.asarray(count_predictions),
            checkpoint["count_labels"],
        ),
        "mean_predicted_quality": float(np.mean(quality_values)) if quality_values else 0.0,
    }
    save_report(report, args.output)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    print(f"REPORT={args.output.resolve()}")
    print("RESULT=PASS_EVALUATION_COMPLETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

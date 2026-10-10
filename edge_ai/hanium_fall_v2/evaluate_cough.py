"""Evaluate a trained cough/confounder checkpoint on a held-out split."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from .metrics import classification_report, save_report


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate cough/confounder checkpoint")
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--split", choices=("train", "val", "test"), default="test")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--output", type=Path, default=Path("reports/cough_test_metrics.json"))
    args = parser.parse_args()

    import torch
    from torch.utils.data import DataLoader

    from .cough_dataset import CoughWindowDataset
    from .health_model import cough_model_from_checkpoint

    device = torch.device(
        "cuda" if args.device == "auto" and torch.cuda.is_available() else
        "cpu" if args.device == "auto" else args.device
    )
    checkpoint = torch.load(args.checkpoint, map_location=device, weights_only=False)
    model = cough_model_from_checkpoint(checkpoint, device)
    dataset = CoughWindowDataset(args.manifest, args.split, augment=False)
    loader = DataLoader(dataset, batch_size=args.batch_size, shuffle=False, num_workers=args.workers)
    targets: list[int] = []
    predictions: list[int] = []
    cough_probabilities: list[float] = []
    cough_index = list(checkpoint["labels"]).index("cough")
    with torch.no_grad():
        for batch in loader:
            logits = model(
                batch["features"].to(device),
                batch["node_mask"].to(device),
                batch["node_quality"].to(device),
            )
            probabilities = torch.softmax(logits, dim=1)
            targets.extend(batch["target"].tolist())
            predictions.extend(logits.argmax(1).cpu().tolist())
            cough_probabilities.extend(probabilities[:, cough_index].cpu().tolist())
    report = {
        "schema": "hanium.ruview.cough-evaluation.v1",
        "checkpoint": str(args.checkpoint.resolve()),
        "manifest": str(args.manifest.resolve()),
        "split": args.split,
        "samples": len(dataset),
        "classification": classification_report(
            np.asarray(targets),
            np.asarray(predictions),
            checkpoint["labels"],
        ),
        "mean_cough_probability": float(np.mean(cough_probabilities)) if cough_probabilities else 0.0,
    }
    save_report(report, args.output)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"REPORT={args.output.resolve()}")
    print("RESULT=PASS_COUGH_EVALUATION_COMPLETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

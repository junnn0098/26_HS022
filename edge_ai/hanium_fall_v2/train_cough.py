"""Train the optional classifier that converts CSI burst candidates to coughs."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import numpy as np

from .metrics import classification_report


def run_epoch(model, loader, device, criterion, optimizer=None):
    import torch

    training = optimizer is not None
    model.train(training)
    total = 0.0
    targets: list[int] = []
    predictions: list[int] = []
    for batch in loader:
        features = batch["features"].to(device)
        mask = batch["node_mask"].to(device)
        quality = batch["node_quality"].to(device)
        target = batch["target"].to(device)
        if training:
            optimizer.zero_grad(set_to_none=True)
        with torch.set_grad_enabled(training):
            logits = model(features, mask, quality)
            loss = criterion(logits, target)
            if training:
                loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
                optimizer.step()
        total += float(loss.detach()) * len(target)
        targets.extend(target.cpu().tolist())
        predictions.extend(logits.argmax(1).cpu().tolist())
    return total / max(len(targets), 1), np.asarray(targets), np.asarray(predictions)


def main() -> int:
    parser = argparse.ArgumentParser(description="Train cough/confounder classifier")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("models/cough_v1"))
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--learning-rate", type=float, default=3e-4)
    parser.add_argument("--device", default="auto")
    args = parser.parse_args()
    import torch
    from torch.utils.data import DataLoader

    from .cough_dataset import CoughWindowDataset
    from .health_model import MultiNodeCoughModel

    device = torch.device("cuda" if args.device == "auto" and torch.cuda.is_available() else "cpu" if args.device == "auto" else args.device)
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    labels = manifest["labels"]
    train_data = CoughWindowDataset(args.manifest, "train", augment=True)
    val_data = CoughWindowDataset(args.manifest, "val", augment=False)
    train_loader = DataLoader(train_data, batch_size=args.batch_size, shuffle=True, num_workers=args.workers)
    val_loader = DataLoader(val_data, batch_size=args.batch_size, shuffle=False, num_workers=args.workers)
    counts = np.bincount([int(item["label_index"]) for item in manifest["samples"] if item["split"] == "train"], minlength=len(labels)).astype(np.float64)
    if np.any(counts == 0):
        raise ValueError(f"training split missing labels: {np.flatnonzero(counts == 0).tolist()}")
    weights = counts.sum() / (len(labels) * counts)
    criterion = torch.nn.CrossEntropyLoss(weight=torch.tensor(weights, dtype=torch.float32, device=device), label_smoothing=0.03)
    model_config = {
        "feature_channels": int(manifest["feature_config"]["feature_channels"]),
        "embedding_dim": 96,
        "classes": len(labels),
        "dropout": 0.20,
    }
    model = MultiNodeCoughModel(**model_config).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate, weight_decay=1e-4)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    best_path = args.output_dir / "best_cough_model.pt"
    best_f1 = -1.0
    stale = 0
    for epoch in range(1, args.epochs + 1):
        train_loss, _, _ = run_epoch(model, train_loader, device, criterion, optimizer)
        val_loss, targets, predictions = run_epoch(model, val_loader, device, criterion)
        report = classification_report(targets, predictions, labels)
        record = {"epoch": epoch, "train_loss": round(train_loss, 6), "val_loss": round(val_loss, 6), "macro_f1": report["macro_f1"], "accuracy": report["accuracy"]}
        print(json.dumps(record, separators=(",", ":")), flush=True)
        if report["macro_f1"] > best_f1:
            best_f1 = float(report["macro_f1"])
            stale = 0
            checkpoint = {
                "schema": "hanium.ruview.cough-checkpoint.v1",
                "model_state_dict": model.state_dict(),
                "model_config": model_config,
                "feature_config": manifest["feature_config"],
                "labels": labels,
                "val_report": report,
                "manifest_path": str(args.manifest.resolve()),
            }
            temporary = best_path.with_suffix(".tmp.pt")
            torch.save(checkpoint, temporary)
            os.replace(temporary, best_path)
        else:
            stale += 1
        if stale >= 10:
            break
    print(f"BEST_COUGH_MODEL={best_path.resolve()} BEST_MACRO_F1={best_f1:.6f}")
    print("RESULT=PASS_COUGH_TRAINING_COMPLETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


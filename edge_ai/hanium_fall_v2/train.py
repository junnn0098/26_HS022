"""Train the canonical 64-channel variable-node activity/count model."""

from __future__ import annotations

import argparse
import json
import os
import random
import time
from pathlib import Path

import numpy as np

from .dataset import CsiWindowDataset
from .metrics import classification_report


def seed_everything(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)


def class_weights(samples: list[dict], key: str, classes: int, torch, device):
    counts = np.zeros(classes, dtype=np.float64)
    for sample in samples:
        if sample["split"] == "train":
            counts[int(sample[key])] += 1
    if np.any(counts == 0):
        missing = np.flatnonzero(counts == 0).tolist()
        raise ValueError(f"training split is missing classes for {key}: {missing}")
    weights = counts.sum() / (classes * counts)
    weights = np.clip(weights, 0.25, 4.0).astype(np.float32)
    return torch.tensor(weights, device=device)


def run_epoch(model, loader, device, activity_loss, count_loss, optimizer=None):
    import torch

    training = optimizer is not None
    model.train(training)
    total_loss = 0.0
    targets: list[int] = []
    activity_predictions: list[int] = []
    count_targets: list[int] = []
    count_predictions: list[int] = []
    for batch in loader:
        features = batch["features"].to(device, non_blocking=True)
        node_mask = batch["node_mask"].to(device, non_blocking=True)
        node_quality = batch["node_quality"].to(device, non_blocking=True)
        activity_target = batch["activity"].to(device, non_blocking=True)
        count_target = batch["count"].to(device, non_blocking=True)
        quality_target = batch["quality_target"].to(device, non_blocking=True)
        if training:
            optimizer.zero_grad(set_to_none=True)
        with torch.set_grad_enabled(training):
            outputs = model(features, node_mask, node_quality)
            loss_activity = activity_loss(outputs["activity_logits"], activity_target)
            loss_count = count_loss(outputs["count_logits"], count_target)
            loss_quality = torch.nn.functional.mse_loss(outputs["quality"], quality_target)
            loss = loss_activity + 0.4 * loss_count + 0.1 * loss_quality
            if training:
                loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
                optimizer.step()
        total_loss += float(loss.detach()) * len(activity_target)
        targets.extend(activity_target.cpu().tolist())
        activity_predictions.extend(outputs["activity_logits"].argmax(1).cpu().tolist())
        count_targets.extend(count_target.cpu().tolist())
        count_predictions.extend(outputs["count_logits"].argmax(1).cpu().tolist())
    return {
        "loss": total_loss / max(len(targets), 1),
        "activity_targets": np.asarray(targets),
        "activity_predictions": np.asarray(activity_predictions),
        "count_targets": np.asarray(count_targets),
        "count_predictions": np.asarray(count_predictions),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Train Hanium RuView Fall V2")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("models/run_v1"))
    parser.add_argument("--epochs", type=int, default=80)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--learning-rate", type=float, default=3e-4)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--patience", type=int, default=12)
    parser.add_argument("--seed", type=int, default=20260828)
    parser.add_argument("--device", default="auto")
    args = parser.parse_args()

    import torch
    from torch import nn
    from torch.utils.data import DataLoader

    from .model import MultiNodeFallModel

    seed_everything(args.seed)
    torch.manual_seed(args.seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(args.seed)
    device = torch.device(
        "cuda" if args.device == "auto" and torch.cuda.is_available() else
        "cpu" if args.device == "auto" else args.device
    )
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    activity_labels = manifest["activity_labels"]
    count_labels = manifest["count_labels"]
    train_dataset = CsiWindowDataset(args.manifest, "train", augment=True)
    val_dataset = CsiWindowDataset(args.manifest, "val", augment=False)
    train_loader = DataLoader(
        train_dataset,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=args.workers,
        pin_memory=device.type == "cuda",
    )
    val_loader = DataLoader(
        val_dataset,
        batch_size=args.batch_size,
        shuffle=False,
        num_workers=args.workers,
        pin_memory=device.type == "cuda",
    )

    model_config = {
        "feature_channels": int(manifest["feature_config"]["feature_channels"]),
        "embedding_dim": 128,
        "activity_classes": len(activity_labels),
        "count_classes": len(count_labels),
        "dropout": 0.20,
    }
    model = MultiNodeFallModel(**model_config).to(device)
    activity_weight = class_weights(manifest["samples"], "activity_index", len(activity_labels), torch, device)
    count_weight = class_weights(manifest["samples"], "count_index", len(count_labels), torch, device)
    activity_loss = nn.CrossEntropyLoss(weight=activity_weight, label_smoothing=0.03)
    count_loss = nn.CrossEntropyLoss(weight=count_weight, label_smoothing=0.02)
    optimizer = torch.optim.AdamW(
        model.parameters(), lr=args.learning_rate, weight_decay=args.weight_decay
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    best_path = args.output_dir / "best_model.pt"
    history: list[dict] = []
    best_macro_f1 = -1.0
    stale_epochs = 0
    started = time.time()

    print(f"TRAINING device={device} train={len(train_dataset)} val={len(val_dataset)}")
    for epoch in range(1, args.epochs + 1):
        train_result = run_epoch(model, train_loader, device, activity_loss, count_loss, optimizer)
        val_result = run_epoch(model, val_loader, device, activity_loss, count_loss)
        activity_report = classification_report(
            val_result["activity_targets"], val_result["activity_predictions"], activity_labels
        )
        count_report = classification_report(
            val_result["count_targets"], val_result["count_predictions"], count_labels
        )
        record = {
            "epoch": epoch,
            "train_loss": round(train_result["loss"], 6),
            "val_loss": round(val_result["loss"], 6),
            "activity_macro_f1": activity_report["macro_f1"],
            "activity_accuracy": activity_report["accuracy"],
            "count_macro_f1": count_report["macro_f1"],
            "count_accuracy": count_report["accuracy"],
            "learning_rate": optimizer.param_groups[0]["lr"],
        }
        history.append(record)
        print(json.dumps(record, separators=(",", ":")), flush=True)
        score = float(activity_report["macro_f1"])
        if score > best_macro_f1:
            best_macro_f1 = score
            stale_epochs = 0
            checkpoint = {
                "schema": "hanium.ruview.model-checkpoint.v1",
                "model_state_dict": model.state_dict(),
                "model_config": model_config,
                "feature_config": manifest["feature_config"],
                "activity_labels": activity_labels,
                "count_labels": count_labels,
                "manifest_path": str(args.manifest.resolve()),
                "manifest_seed": manifest.get("seed"),
                "epoch": epoch,
                "val_activity_report": activity_report,
                "val_count_report": count_report,
                "training_seconds": time.time() - started,
            }
            temporary = best_path.with_suffix(".tmp.pt")
            torch.save(checkpoint, temporary)
            os.replace(temporary, best_path)
        else:
            stale_epochs += 1
        scheduler.step()
        if stale_epochs >= args.patience:
            print(f"EARLY_STOP epoch={epoch} patience={args.patience}")
            break

    (args.output_dir / "history.json").write_text(
        json.dumps(history, indent=2) + "\n", encoding="utf-8"
    )
    print(f"BEST_MODEL={best_path.resolve()} BEST_ACTIVITY_MACRO_F1={best_macro_f1:.6f}")
    print("RESULT=PASS_TRAINING_COMPLETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

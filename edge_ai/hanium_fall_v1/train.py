"""Train and cross-validate the 134ch x 500 1D-CNN on the measured dataset.

Split protocols
  random     label-stratified 80/20 split of windows
  recording  5-fold split by recording: no recording appears in both train and test
  temporal   train on the 2026-07-08..07-15 batches, test on the 07-24 and 07-28 batches

Examples (from edge_ai/)
  python -m hanium_fall_v1.train --protocol random --channels all --seeds 0 1 2 3 4 --out ../experiments/results/v1/random_all
  python -m hanium_fall_v1.train --final --channels csi --save models/fall_1dcnn_csi.pth
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import time
from pathlib import Path

import numpy as np

from .data import DEFAULT_METADATA, DEFAULT_NPZ_DIR, load_windows, preprocess
from .metrics import binary_metrics, per_label, summarize
from .model import FALL_INDEX, CSI1DCNN, parameter_count

TEMPORAL_TRAIN = ("b1_0708_0709", "b2_0715")
TEMPORAL_TEST = ("b3_0724", "b4_0728")


def class_index(rows: list[dict]) -> np.ndarray:
    """Team convention: class 0 = fall, class 1 = non-fall."""
    return np.array([FALL_INDEX if row["is_fall"] else 1 - FALL_INDEX for row in rows], dtype=np.int64)


def split_random(rows: list[dict], seed: int, test_fraction: float = 0.2) -> list[tuple[np.ndarray, np.ndarray]]:
    rng = np.random.default_rng(seed)
    test = []
    labels = np.array([row["label"] for row in rows])
    for label in sorted(set(labels)):
        index = np.flatnonzero(labels == label)
        rng.shuffle(index)
        test.extend(index[: max(1, round(len(index) * test_fraction))])
    test = np.sort(np.array(test))
    train = np.setdiff1d(np.arange(len(rows)), test)
    return [(train, test)]


def split_recordings(rows: list[dict], folds: int, seed: int) -> list[tuple[np.ndarray, np.ndarray]]:
    """Assign whole recordings to folds, spreading every label over the folds."""
    rng = np.random.default_rng(seed)
    recordings = {}
    for row in rows:
        recordings.setdefault(row["recording"], (row["category"], row["label"]))
    keyed = [(category, label, rng.random(), name) for name, (category, label) in recordings.items()]
    fold_of = {name: i % folds for i, (*_, name) in enumerate(sorted(keyed))}
    assignment = np.array([fold_of[row["recording"]] for row in rows])
    return [(np.flatnonzero(assignment != k), np.flatnonzero(assignment == k)) for k in range(folds)]


def split_temporal(rows: list[dict]) -> list[tuple[np.ndarray, np.ndarray]]:
    batches = np.array([row["batch"] for row in rows])
    return [(np.flatnonzero(np.isin(batches, TEMPORAL_TRAIN)), np.flatnonzero(np.isin(batches, TEMPORAL_TEST)))]


def fit(x: np.ndarray, y: np.ndarray, *, epochs: int, seed: int, lr: float, batch_size: int):
    import torch

    torch.manual_seed(seed)
    rng = np.random.default_rng(seed)
    model = CSI1DCNN()
    counts = np.bincount(y, minlength=2).astype(np.float64)
    weights = torch.tensor(counts.sum() / (2 * np.maximum(counts, 1)), dtype=torch.float32)
    criterion = torch.nn.CrossEntropyLoss(weight=weights)  # weighted CE: missed falls cost more
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    inputs, targets = torch.from_numpy(x), torch.from_numpy(y)
    history = []
    for _ in range(epochs):
        model.train()
        order = rng.permutation(len(y))
        total = 0.0
        for start in range(0, len(order), batch_size):
            batch = order[start:start + batch_size]
            if len(batch) < 2:
                continue
            optimizer.zero_grad(set_to_none=True)
            loss = criterion(model(inputs[batch]), targets[batch])
            loss.backward()
            optimizer.step()
            total += float(loss.detach()) * len(batch)
        scheduler.step()
        history.append(round(total / len(order), 5))
    return model, history


def predict(model, x: np.ndarray, batch_size: int = 256) -> np.ndarray:
    import torch

    model.eval()
    probabilities = []
    with torch.no_grad():
        for start in range(0, len(x), batch_size):
            logits = model(torch.from_numpy(x[start:start + batch_size]))
            probabilities.append(torch.softmax(logits, dim=1)[:, FALL_INDEX].numpy())
    return np.concatenate(probabilities)


def file_digest(path: Path) -> str:
    """SHA-256 of the file; text files are hashed with LF line endings so Windows and Linux agree."""
    data = Path(path).read_bytes()
    if Path(path).suffix in (".csv", ".json", ".py", ".md", ".txt"):
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def environment() -> dict:
    import platform

    import torch

    return {"python": platform.python_version(), "numpy": np.__version__, "torch": torch.__version__}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--npz-dir", type=Path, default=DEFAULT_NPZ_DIR)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--batches", nargs="*", help="use only these dataset batches (default: all)")
    parser.add_argument("--protocol", choices=("random", "recording", "temporal"), default="recording")
    parser.add_argument("--channels", choices=("all", "csi", "lltf", "non_csi"), default="csi")
    parser.add_argument("--folds", type=int, default=5)
    parser.add_argument("--seeds", type=int, nargs="+", default=[0])
    parser.add_argument("--epochs", type=int, default=25)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--threads", type=int, default=4, help="torch CPU threads (small values are faster here)")
    parser.add_argument("--out", type=Path, help="folder for per-fold metrics and predictions")
    parser.add_argument("--final", action="store_true", help="train once on every window and save weights")
    parser.add_argument("--save", type=Path, help="weights path for --final")
    args = parser.parse_args()

    import torch

    torch.set_num_threads(max(1, min(args.threads, os.cpu_count() or 1)))
    torch.use_deterministic_algorithms(True, warn_only=True)
    windows, rows = load_windows(args.npz_dir, args.metadata, args.batches)
    x = preprocess(windows, args.channels)
    del windows
    y = class_index(rows)
    is_fall = np.array([row["is_fall"] for row in rows])
    config = {"channels": args.channels, "epochs": args.epochs, "lr": args.lr, "batch_size": args.batch_size,
              "loss": "weighted cross-entropy", "optimizer": "Adam(wd=1e-4) + cosine", "threshold": 0.5,
              "parameters": parameter_count(CSI1DCNN()),
              "metadata_sha256": file_digest(args.metadata), "threads": args.threads, "environment": environment()}

    if args.final:
        if not args.save:
            parser.error("--final needs --save")
        started = time.time()
        model, history = fit(x, y, epochs=args.epochs, seed=args.seeds[0], lr=args.lr, batch_size=args.batch_size)
        args.save.parent.mkdir(parents=True, exist_ok=True)
        torch.save(model.state_dict(), args.save)
        card = {**config, "seed": args.seeds[0], "trained_on_windows": len(rows),
                "trained_on_falls": int(is_fall.sum()), "loss_history": history,
                "train_seconds": round(time.time() - started, 1), "weights_sha256": file_digest(args.save)}
        args.save.with_suffix(".json").write_text(json.dumps(card, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"saved {args.save} ({card['weights_sha256'][:12]})")
        return

    if not args.out:
        parser.error("--out is required unless --final")
    args.out.mkdir(parents=True, exist_ok=True)
    runs, predictions = [], []
    for seed in args.seeds:
        if args.protocol == "random":
            splits = split_random(rows, seed)
        elif args.protocol == "recording":
            splits = split_recordings(rows, args.folds, seed)
        else:
            splits = split_temporal(rows)
        for fold, (train, test) in enumerate(splits):
            started = time.time()
            model, history = fit(x[train], y[train], epochs=args.epochs, seed=seed, lr=args.lr,
                                 batch_size=args.batch_size)
            p_fall = predict(model, x[test])
            test_rows = [rows[i] for i in test]
            result = binary_metrics(is_fall[test], p_fall)
            result.update({"seed": seed, "fold": fold, "train_windows": int(len(train)),
                           "test_recordings": len({r["recording"] for r in test_rows}),
                           "seconds": round(time.time() - started, 1), "loss_history": history,
                           "per_label": per_label(test_rows, p_fall)})
            runs.append(result)
            predictions.extend((row["window_id"], seed, fold, round(float(p), 5)) for row, p in zip(test_rows, p_fall))
            print(f"[{args.protocol}/{args.channels}] seed {seed} fold {fold}: recall {result['recall']} "
                  f"precision {result['precision']} f1 {result['f1']} auroc {result['auroc']} ({result['seconds']}s)",
                  flush=True)

    summary = {"protocol": args.protocol, "batches": args.batches or "all", **config, "runs": len(runs),
               "summary": summarize(runs)}
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    (args.out / "runs.json").write_text(json.dumps(runs, indent=1, ensure_ascii=False), encoding="utf-8")
    with (args.out / "predictions.csv").open("w", encoding="utf-8") as handle:
        handle.write("window_id,seed,fold,p_fall\n")
        handle.writelines(f"{w},{s},{f},{p}\n" for w, s, f, p in predictions)
    print(json.dumps(summary["summary"], ensure_ascii=False))


if __name__ == "__main__":
    main()

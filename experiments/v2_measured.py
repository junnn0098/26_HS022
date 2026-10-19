"""Train the v2 multi-node model on the measured dataset with the v1 splits.

Same 2,217 window ids and start times, same recording-level labels, same
recording/temporal splits as the v1 experiments; the input pipeline and model differ:
  v1  134 interleaved channels x 500 packets (median 5.0 s), one global z-score  (CSI1DCNN)
  v2  4 nodes x (LLTF log-amp, dynamic amp, phase delta, RSSI) x 160 frames at 32 Hz,
      a fixed 5 s from the window start  (hanium_fall_v2.features + MultiNodeFallModel)

Needs the v2 session files (python dataset/tools/download.py --v2, or
dataset/tools/raw_to_v2.py from the raw recordings). One fold takes about 20 minutes
on 2 CPU threads; --fold-index and --merge split a protocol over several processes.

  python experiments/v2_measured.py --protocol recording --out experiments/results/v2_measured/recording
  python experiments/v2_measured.py --protocol temporal --seeds 0 1 2 --out experiments/results/v2_measured/temporal
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "edge_ai"))

from hanium_fall_v1.data import read_metadata  # noqa: E402
from hanium_fall_v1.metrics import binary_metrics, per_label, summarize  # noqa: E402
from hanium_fall_v1.train import split_recordings, split_temporal  # noqa: E402
from hanium_fall_v2.config import FeatureConfig  # noqa: E402
from hanium_fall_v2.dataset import CsiWindowDataset  # noqa: E402
from hanium_fall_v2.features import assemble_multinode_window  # noqa: E402
from hanium_fall_v2.labels import ACTIVITIES  # noqa: E402

FALL = ACTIVITIES.index("fall")
ONE_PERSON = 1  # COUNT_LABELS = ("0", "1", "2", "3plus")
NODES = (1, 2, 3, 4)


def build_features(rows: list[dict], sessions: Path, cache: Path, widths: tuple[int, ...] = ()) -> dict[str, np.ndarray]:
    if cache.exists():
        with np.load(cache) as data:
            if list(data["window_id"]) == [row["window_id"] for row in rows]:
                return {key: data[key] for key in data.files}
    config = FeatureConfig()
    features = np.zeros((len(rows), config.max_nodes, config.feature_channels, config.window_frames), np.float16)
    masks = np.zeros((len(rows), config.max_nodes), bool)
    quality = np.zeros((len(rows), config.max_nodes), np.float32)
    activity = np.zeros(len(rows), np.int64)
    loaded: dict[str, dict] = {}
    for index, row in enumerate(rows):
        if row["recording"] not in loaded:
            loaded.clear()
            with np.load(sessions / f"{row['recording']}.npz") as data:
                keep = np.isin(data["source_subcarriers"], widths) if widths else slice(None)
                loaded[row["recording"]] = {key: data[key][keep] for key in
                                            ("received_monotonic_ns", "node_id", "iq", "rssi_dbm")}
                loaded[row["recording"]]["meta_json"] = data["meta_json"]
        session = loaded[row["recording"]]
        start = int(datetime.fromisoformat(row["ts_start_utc"].replace("Z", "+00:00")).timestamp() * 1e9)
        window = assemble_multinode_window(session["received_monotonic_ns"], session["node_id"], session["iq"],
                                           session["rssi_dbm"], NODES, start, config)
        features[index] = window.features
        masks[index] = window.node_mask
        quality[index] = window.node_quality
        activity[index] = ACTIVITIES.index(json.loads(str(session["meta_json"]))["activity"])
    cache.parent.mkdir(parents=True, exist_ok=True)
    np.savez(cache, features=features, masks=masks, quality=quality, activity=activity,
             window_id=np.array([row["window_id"] for row in rows]))
    return {"features": features, "masks": masks, "quality": quality, "activity": activity}


def fit(data: dict, train: np.ndarray, *, epochs: int, seed: int, batch_size: int = 32, lr: float = 1e-3):
    """v2 training loss (hanium_fall_v2/train.py): activity + 0.4 x count + 0.1 x quality.

    Every recording has one person, so the count target is the '1' bucket and the
    quality target is the window's mean node quality. Falls are the largest class
    (44 %), so the activity loss is not class-weighted here: frequency weights would
    give the fall class about 1/7 of the loss of the rare labels.
    """
    import torch

    from hanium_fall_v2.model import MultiNodeFallModel

    torch.manual_seed(seed)
    np.random.seed(seed)
    rng = np.random.default_rng(seed)
    model = MultiNodeFallModel()
    activity_loss = torch.nn.CrossEntropyLoss(label_smoothing=0.03)
    count_loss = torch.nn.CrossEntropyLoss(label_smoothing=0.02)
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    history = []
    for _ in range(epochs):
        model.train()
        order = rng.permutation(train)
        total = 0.0
        for start in range(0, len(order), batch_size):
            batch = order[start:start + batch_size]
            if len(batch) < 2:
                continue
            x = np.stack([CsiWindowDataset._augment(None, data["features"][i].astype(np.float32), data["masks"][i])
                          for i in batch])
            quality = torch.from_numpy(data["quality"][batch])
            mask = torch.from_numpy(data["masks"][batch])
            out = model(torch.from_numpy(x), mask, quality)
            quality_target = (quality * mask).sum(1) / mask.sum(1).clamp(min=1)
            loss = (activity_loss(out["activity_logits"], torch.from_numpy(data["activity"][batch]))
                    + 0.4 * count_loss(out["count_logits"], torch.full((len(batch),), ONE_PERSON))
                    + 0.1 * torch.nn.functional.mse_loss(out["quality"], quality_target))
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            total += float(loss.detach()) * len(batch)
        scheduler.step()
        history.append(round(total / len(order), 5))
    return model, history


def predict(model, data: dict, index: np.ndarray, batch_size: int = 128) -> np.ndarray:
    import torch

    model.eval()
    out = []
    with torch.no_grad():
        for start in range(0, len(index), batch_size):
            batch = index[start:start + batch_size]
            logits = model(torch.from_numpy(data["features"][batch].astype(np.float32)),
                           torch.from_numpy(data["masks"][batch]),
                           torch.from_numpy(data["quality"][batch]))["activity_logits"]
            out.append(torch.softmax(logits, dim=1)[:, FALL].numpy())
    return np.concatenate(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sessions", type=Path, default=ROOT / "dataset" / "v2_sessions")
    parser.add_argument("--cache", type=Path, help="feature cache (default: dataset/cache/v2_features[_w<widths>].npz)")
    parser.add_argument("--widths", type=int, nargs="*", default=[],
                        help="keep only packets of these raw widths (64/128/192); default keeps all")
    parser.add_argument("--protocol", choices=("recording", "temporal"), default="recording")
    parser.add_argument("--folds", type=int, default=5)
    parser.add_argument("--seeds", type=int, nargs="+", default=[0])
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--fold-index", type=int, help="run only this fold (to split a protocol over processes)")
    parser.add_argument("--merge", type=Path, nargs="+", help="merge the runs of these output folders into --out")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--save", type=Path, help="train once on every window and save weights here")
    args = parser.parse_args()

    if args.merge:
        merge(args.merge, args.out)
        return

    import torch

    torch.set_num_threads(max(1, min(args.threads, os.cpu_count() or 1)))
    rows = read_metadata()
    suffix = "_w" + "-".join(map(str, args.widths)) if args.widths else ""
    cache = args.cache or ROOT / "dataset" / "cache" / f"v2_features{suffix}.npz"
    data = build_features(rows, args.sessions, cache, tuple(args.widths))
    is_fall = np.array([row["is_fall"] for row in rows])
    args.out.mkdir(parents=True, exist_ok=True)
    config = {"pipeline": "v2 features + MultiNodeFallModel", "packet_widths": args.widths or "all",
              "epochs": args.epochs, "threshold": 0.5,
              "loss": "CE(10 activities, label smoothing 0.03) + 0.4 CE(count) + 0.1 MSE(quality)",
              "optimizer": "AdamW 1e-3 + cosine, grad-norm clip 5", "augmentation": "hanium_fall_v2 dataset augmentation",
              "window": "ts_start_utc + 5 s (v2 uses a fixed time span, v1 uses 500 packets)",
              "p_fall": "softmax(activity)[fall]",
              "nodes_masked_share": round(float(1 - data["masks"].mean()), 4)}

    if args.save:
        from dataclasses import asdict

        from hanium_fall_v2.config import ModelConfig
        from hanium_fall_v2.fall_checkpoint import (
            CHECKPOINT_SCHEMA, COUNT_LABELS, EXPECTED_FEATURE_CONFIG, require_live_ready_fall_checkpoint,
        )

        model, history = fit(data, np.arange(len(rows)), epochs=args.epochs, seed=args.seeds[0])
        checkpoint = {
            "schema": CHECKPOINT_SCHEMA, "model_state_dict": model.state_dict(),
            "model_config": asdict(ModelConfig()), "feature_config": dict(EXPECTED_FEATURE_CONFIG),
            "activity_labels": list(ACTIVITIES), "count_labels": list(COUNT_LABELS),
            "trained_on": "dataset/metadata/windows.csv (2,217 measured windows, recording-level labels)",
            "count_head_note": "every training window has one person; the count head always predicts '1'",
        }
        report = require_live_ready_fall_checkpoint(checkpoint, torch)
        args.save.parent.mkdir(parents=True, exist_ok=True)
        torch.save(checkpoint, args.save)
        card = {**config, "trained_on_windows": len(rows), "seed": args.seeds[0], "loss_history": history,
                "checkpoint_check": report["result"]}
        args.save.with_suffix(".json").write_text(json.dumps(card, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"saved {args.save} ({report['result']})")
        return

    runs, predictions = [], []
    for seed in args.seeds:
        splits = split_recordings(rows, args.folds, seed) if args.protocol == "recording" else split_temporal(rows)
        for fold, (train, test) in enumerate(splits):
            if args.fold_index is not None and fold != args.fold_index:
                continue
            started = time.time()
            model, history = fit(data, train, epochs=args.epochs, seed=seed)
            p_fall = predict(model, data, test)
            test_rows = [rows[i] for i in test]
            result = binary_metrics(is_fall[test], p_fall)
            train_fit = binary_metrics(is_fall[train], predict(model, data, train))
            result.update({"seed": seed, "fold": fold, "train_windows": int(len(train)),
                           "train_recall": train_fit["recall"], "train_auroc": train_fit["auroc"],
                           "test_recordings": len({r["recording"] for r in test_rows}),
                           "seconds": round(time.time() - started, 1), "loss_history": history,
                           "per_label": per_label(test_rows, p_fall)})
            runs.append(result)
            predictions.extend((row["window_id"], seed, fold, round(float(p), 5)) for row, p in zip(test_rows, p_fall))
            print(f"[v2/{args.protocol}] seed {seed} fold {fold}: recall {result['recall']} precision "
                  f"{result['precision']} f1 {result['f1']} auroc {result['auroc']} | train recall "
                  f"{result['train_recall']} auroc {result['train_auroc']} ({result['seconds']}s)", flush=True)

    write_results(args.out, {"protocol": args.protocol, **config}, runs, predictions)


def write_results(out: Path, header: dict, runs: list[dict], predictions: list[tuple]) -> None:
    summary = {**header, "runs": len(runs), "summary": summarize(runs),
               "train_fit": {key: summarize(runs, keys=(key,)).get(key) for key in ("train_recall", "train_auroc")}}
    out.mkdir(parents=True, exist_ok=True)
    (out / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    (out / "runs.json").write_text(json.dumps(runs, indent=1, ensure_ascii=False), encoding="utf-8")
    with (out / "predictions.csv").open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("window_id,seed,fold,p_fall\n")
        handle.writelines(f"{w},{s},{f},{p}\n" for w, s, f, p in predictions)
    print(json.dumps(summary["summary"], ensure_ascii=False))


def merge(parts: list[Path], out: Path) -> None:
    """Combine folders written with --fold-index into one result folder."""
    header, runs, predictions = None, [], []
    for part in parts:
        summary = json.loads((part / "summary.json").read_text(encoding="utf-8"))
        header = header or {k: v for k, v in summary.items() if k not in ("runs", "summary", "train_fit")}
        runs.extend(json.loads((part / "runs.json").read_text(encoding="utf-8")))
        with (part / "predictions.csv").open(encoding="utf-8") as handle:
            next(handle)
            predictions.extend(tuple(line.strip().split(",")) for line in handle if line.strip())
    runs.sort(key=lambda run: (run["seed"], run["fold"]))
    write_results(out, header, runs, predictions)


if __name__ == "__main__":
    main()

"""Evaluate saved 1D-CNN weights on dataset batches.

Example (from edge_ai/)
  python -m hanium_fall_v1.evaluate --weights hanium_fall_v1/weights/team_v1_0717.pth \
      --channels all --batches b3_0724 b4_0728 --out ../experiments/results/v1/team_model_holdout.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from .data import DEFAULT_METADATA, DEFAULT_NPZ_DIR, load_windows, preprocess
from .metrics import binary_metrics, per_label
from .model import CSI1DCNN
from .train import file_digest, predict


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--weights", type=Path, required=True)
    parser.add_argument("--channels", choices=("all", "csi", "lltf", "non_csi"), default="all",
                        help="must match how the weights were trained (team weights: all)")
    parser.add_argument("--npz-dir", type=Path, default=DEFAULT_NPZ_DIR)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--batches", nargs="*", help="dataset batches to evaluate (default: all)")
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    import torch

    model = CSI1DCNN()
    model.load_state_dict(torch.load(args.weights, map_location="cpu", weights_only=True))
    windows, rows = load_windows(args.npz_dir, args.metadata, args.batches)
    p_fall = predict(model, preprocess(windows, args.channels))
    is_fall = np.array([row["is_fall"] for row in rows])

    report = {
        "weights": args.weights.name, "weights_sha256": file_digest(args.weights), "channels": args.channels,
        "batches": args.batches or sorted({row["batch"] for row in rows}),
        "overall": binary_metrics(is_fall, p_fall, args.threshold),
        "by_batch": {}, "per_label": per_label(rows, p_fall, args.threshold),
    }
    for batch in sorted({row["batch"] for row in rows}):
        index = np.array([row["batch"] == batch for row in rows])
        report["by_batch"][batch] = binary_metrics(is_fall[index], p_fall[index], args.threshold)

    text = json.dumps(report, indent=2, ensure_ascii=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()

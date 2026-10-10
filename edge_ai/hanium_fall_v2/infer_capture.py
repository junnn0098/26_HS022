"""Run a trained checkpoint over one saved capture for debugging and replay."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from .config import FeatureConfig, RuntimeConfig
from .dataset import load_capture
from .fall_state import FallStateMachine
from .features import assemble_multinode_window
from .labels import display_activity


def main() -> int:
    parser = argparse.ArgumentParser(description="Offline CSI capture inference")
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--stride-seconds", type=float, default=0.5)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    import torch

    from .fall_checkpoint import require_live_ready_fall_checkpoint
    from .model import model_from_checkpoint

    device = torch.device(
        "cuda" if args.device == "auto" and torch.cuda.is_available() else
        "cpu" if args.device == "auto" else args.device
    )
    checkpoint = torch.load(args.checkpoint, map_location=device, weights_only=False)
    require_live_ready_fall_checkpoint(checkpoint, torch)
    model = model_from_checkpoint(checkpoint, device)
    raw_config = checkpoint["feature_config"]
    config = FeatureConfig(
        subcarriers=int(raw_config["subcarriers"]),
        sample_rate_hz=int(raw_config["sample_rate_hz"]),
        window_seconds=float(raw_config["window_seconds"]),
        max_nodes=int(raw_config["max_nodes"]),
    )
    activity_labels = checkpoint["activity_labels"]
    count_labels = checkpoint["count_labels"]
    capture = load_capture(str(args.capture.resolve()))
    meta = capture["meta"]
    timestamps = capture["received_monotonic_ns"]
    expected_nodes = [int(value) for value in meta.get("expected_nodes", [1])]
    first_ns = int(timestamps.min())
    duration = float(meta["capture_elapsed_seconds"])
    state_machine = FallStateMachine(RuntimeConfig())
    output = args.output.open("w", encoding="utf-8") if args.output else None
    starts = np.arange(0.0, max(0.0, duration - config.window_seconds) + 1e-9, args.stride_seconds)
    try:
        for start_seconds in starts:
            window = assemble_multinode_window(
                timestamps,
                capture["node_id"],
                capture["iq"],
                capture["rssi_dbm"],
                expected_nodes,
                first_ns + int(start_seconds * 1e9),
                config,
            )
            if not np.any(window.node_mask):
                continue
            with torch.no_grad():
                results = model(
                    torch.from_numpy(window.features).unsqueeze(0).to(device),
                    torch.from_numpy(window.node_mask).unsqueeze(0).to(device),
                    torch.from_numpy(window.node_quality).unsqueeze(0).to(device),
                )
                activity = torch.softmax(results["activity_logits"], 1)[0].cpu().numpy()
                count = torch.softmax(results["count_logits"], 1)[0].cpu().numpy()
                model_quality = float(results["quality"][0].cpu())
            probabilities = {label: float(activity[index]) for index, label in enumerate(activity_labels)}
            count_index = int(np.argmax(count))
            quality = min(model_quality, float(np.mean(window.node_quality[window.node_mask])))
            decision = state_machine.update(
                float(start_seconds + config.window_seconds),
                probabilities,
                quality,
                count_labels[count_index],
            )
            record = {
                "time_seconds": round(float(start_seconds + config.window_seconds), 3),
                "activity": display_activity(activity_labels[int(np.argmax(activity))]),
                "raw_activity": activity_labels[int(np.argmax(activity))],
                "activity_confidence": float(np.max(activity)),
                "people_count": count_labels[count_index],
                "quality": quality,
                "fall": decision.to_dict(),
            }
            line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
            print(line)
            if output:
                output.write(line + "\n")
    finally:
        if output:
            output.close()
    print("RESULT=PASS_OFFLINE_INFERENCE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

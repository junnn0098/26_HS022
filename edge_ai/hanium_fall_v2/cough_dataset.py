"""PyTorch dataset for labelled cough and overnight confounder captures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from .config import FeatureConfig
from .dataset import load_capture
from .features import assemble_multinode_window


class CoughWindowDataset:
    def __init__(self, manifest_path: str | Path, split: str, augment: bool = False) -> None:
        import torch

        self.torch = torch
        self.manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
        self.samples = [item for item in self.manifest["samples"] if item["split"] == split]
        if not self.samples:
            raise ValueError(f"cough manifest has no samples for split={split}")
        raw = self.manifest["feature_config"]
        self.config = FeatureConfig(
            subcarriers=int(raw["subcarriers"]),
            sample_rate_hz=int(raw["sample_rate_hz"]),
            window_seconds=float(raw["window_seconds"]),
            max_nodes=int(raw["max_nodes"]),
        )
        self.augment = augment

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, index: int) -> dict:
        sample = self.samples[index]
        capture = load_capture(sample["path"])
        timestamps = capture["received_monotonic_ns"]
        start_ns = int(np.min(timestamps)) + int(float(sample["start_seconds"]) * 1e9)
        expected_nodes = [int(value) for value in capture["meta"].get("expected_nodes", [1])]
        window = assemble_multinode_window(
            timestamps,
            capture["node_id"],
            capture["iq"],
            capture["rssi_dbm"],
            expected_nodes,
            start_ns,
            self.config,
        )
        features = window.features.copy()
        if self.augment:
            features += np.random.normal(0.0, 0.015, features.shape).astype(np.float32)
            features = np.roll(features, int(np.random.randint(-2, 3)), axis=-1)
        return {
            "features": self.torch.from_numpy(features),
            "node_mask": self.torch.from_numpy(window.node_mask),
            "node_quality": self.torch.from_numpy(window.node_quality),
            "target": self.torch.tensor(int(sample["label_index"]), dtype=self.torch.long),
        }


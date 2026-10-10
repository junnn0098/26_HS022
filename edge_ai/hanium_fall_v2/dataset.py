"""PyTorch dataset backed by raw compressed session captures."""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

import numpy as np

from .config import FeatureConfig
from .features import assemble_multinode_window


@lru_cache(maxsize=12)
def load_capture(path_string: str) -> dict[str, np.ndarray | dict]:
    with np.load(path_string, allow_pickle=False) as data:
        return {
            "meta": json.loads(str(data["meta_json"].item())),
            "received_monotonic_ns": data["received_monotonic_ns"].copy(),
            "node_id": data["node_id"].copy(),
            "iq": data["iq"].copy(),
            "rssi_dbm": data["rssi_dbm"].copy(),
        }


class CsiWindowDataset:
    """Dataset kept importable without torch; torch is required on construction."""

    def __init__(
        self,
        manifest_path: str | Path,
        split: str,
        augment: bool = False,
    ) -> None:
        try:
            import torch
        except ImportError as exc:
            raise RuntimeError("PyTorch is required; use the NVIDIA Jetson PyTorch build") from exc
        self.torch = torch
        self.manifest_path = Path(manifest_path)
        self.manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        self.samples = [item for item in self.manifest["samples"] if item["split"] == split]
        self.augment = augment
        feature = self.manifest["feature_config"]
        self.config = FeatureConfig(
            subcarriers=int(feature["subcarriers"]),
            sample_rate_hz=int(feature["sample_rate_hz"]),
            window_seconds=float(feature["window_seconds"]),
            max_nodes=int(feature["max_nodes"]),
        )
        if not self.samples:
            raise ValueError(f"manifest has no samples for split={split}")

    def __len__(self) -> int:
        return len(self.samples)

    def _augment(self, features: np.ndarray, node_mask: np.ndarray) -> np.ndarray:
        result = features.copy()
        result += np.random.normal(0.0, 0.01, result.shape).astype(np.float32)
        shift = int(np.random.randint(-3, 4))
        result = np.roll(result, shift, axis=-1)
        if np.random.random() < 0.30:
            width = int(np.random.randint(2, 9))
            start = int(np.random.randint(0, max(1, result.shape[-1] - width)))
            result[..., start : start + width] = 0.0
        active_nodes = np.flatnonzero(node_mask)
        if len(active_nodes) > 1 and np.random.random() < 0.15:
            result[int(np.random.choice(active_nodes))] = 0.0
        return result

    def __getitem__(self, index: int) -> dict:
        sample = self.samples[index]
        capture = load_capture(sample["path"])
        timestamps = capture["received_monotonic_ns"]
        first_ns = int(np.min(timestamps))
        start_ns = first_ns + int(float(sample["start_seconds"]) * 1e9)
        meta = capture["meta"]
        expected_nodes = [int(value) for value in meta.get("expected_nodes", [1])]
        window = assemble_multinode_window(
            timestamps,
            capture["node_id"],
            capture["iq"],
            capture["rssi_dbm"],
            expected_nodes,
            start_ns,
            self.config,
        )
        if not np.any(window.node_mask):
            raise ValueError(f"no usable node in sample index={index} path={sample['path']}")
        features = self._augment(window.features, window.node_mask) if self.augment else window.features
        return {
            "features": self.torch.from_numpy(features),
            "node_mask": self.torch.from_numpy(window.node_mask),
            "node_quality": self.torch.from_numpy(window.node_quality),
            "activity": self.torch.tensor(int(sample["activity_index"]), dtype=self.torch.long),
            "count": self.torch.tensor(int(sample["count_index"]), dtype=self.torch.long),
            "quality_target": self.torch.tensor(float(sample["quality_target"]), dtype=self.torch.float32),
            "sample_index": index,
        }


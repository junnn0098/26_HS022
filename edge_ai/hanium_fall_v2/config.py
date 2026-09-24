"""Shared configuration for training and live inference."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class FeatureConfig:
    subcarriers: int = 64
    sample_rate_hz: int = 32
    window_seconds: float = 5.0
    max_nodes: int = 4
    min_node_quality: float = 0.25

    @property
    def window_frames(self) -> int:
        return int(round(self.sample_rate_hz * self.window_seconds))

    @property
    def feature_channels(self) -> int:
        # absolute log amplitude + dynamic amplitude + phase delta + RSSI
        return self.subcarriers * 3 + 1


@dataclass(frozen=True)
class ModelConfig:
    feature_channels: int = 193
    embedding_dim: int = 128
    activity_classes: int = 10
    count_classes: int = 4
    dropout: float = 0.20


@dataclass(frozen=True)
class RuntimeConfig:
    inference_interval_seconds: float = 0.5
    min_quality: float = 0.55
    min_activity_confidence: float = 0.55
    fall_candidate_probability: float = 0.70
    fall_candidate_hits: int = 2
    post_fall_timeout_seconds: float = 8.0
    post_fall_lying_probability: float = 0.55
    post_fall_lying_hits: int = 3
    recovery_probability: float = 0.65
    recovery_hits: int = 2
    confirmed_hold_seconds: float = 30.0


@dataclass(frozen=True)
class HealthConfig:
    """Conservative CSI-only respiratory and cough-candidate settings.

    Heart-rate fields are intentionally absent.  The health monitor emits an
    apnea *suspicion* only after a reliable breathing baseline and never treats
    missing/noisy CSI as proof of apnea.
    """

    enabled: bool = True
    respiratory_sample_rate_hz: int = 10
    respiratory_window_seconds: float = 60.0
    respiratory_min_history_seconds: float = 30.0
    respiratory_min_bpm: float = 6.0
    respiratory_max_bpm: float = 30.0
    respiratory_min_confidence: float = 0.45
    respiratory_min_nodes: int = 2
    respiratory_max_motion_score: float = 0.70
    apnea_enabled: bool = True
    apnea_min_seconds: float = 10.0
    apnea_recent_window_seconds: float = 12.0
    apnea_amplitude_ratio: float = 0.30
    apnea_baseline_updates: int = 3
    assumed_people_when_model_unavailable: int = 1
    cough_enabled: bool = True
    cough_candidate_min_nodes: int = 2
    cough_candidate_z: float = 6.0
    cough_coincidence_seconds: float = 0.35
    cough_refractory_seconds: float = 1.0
    cough_baseline_seconds: float = 20.0
    cough_min_baseline_samples: int = 40
    cough_confirm_probability: float = 0.80


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def save_default_config(path: Path) -> None:
    payload = {
        "feature": asdict(FeatureConfig()),
        "model": asdict(ModelConfig()),
        "runtime": asdict(RuntimeConfig()),
        "health": asdict(HealthConfig()),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

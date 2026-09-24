"""Hardware-free self-test for parser, features, state machine, and optional torch model."""

from __future__ import annotations

import struct

import numpy as np

from .adr018 import HEADER, MAGIC, extract_lltf_iq, parse_adr018
from .config import FeatureConfig, HealthConfig, RuntimeConfig
from .cough import CoughCandidate, CoughCandidateDetector
from .fall_state import FallState, FallStateMachine
from .features import build_node_features
from .respiratory import NodeRespirationEstimate, RespiratoryMonitor


def main() -> int:
    header = HEADER.pack(MAGIC, 1, 1, 192, 2437, 1, -60, -96, 0, 0)
    payload = np.tile(np.asarray([3, 4], dtype=np.int8), 192).tobytes()
    frame = parse_adr018(header + payload)
    assert frame.iq.shape == (1, 192, 2)
    canonical_iq = extract_lltf_iq(frame)
    assert canonical_iq.shape == (1, 64, 2)
    assert np.all(canonical_iq[:, :2, :] == 0)
    config = FeatureConfig()
    frame_count = 165
    timestamps = np.arange(frame_count, dtype=np.int64) * int(1e9 / 33)
    iq = np.repeat(canonical_iq[None], frame_count, axis=0)
    rssi = np.full(frame_count, -60, dtype=np.int8)
    features, quality = build_node_features(timestamps, iq, rssi, 0, config)
    assert features.shape == (config.feature_channels, config.window_frames)
    assert quality > 0.90

    runtime = RuntimeConfig(
        fall_candidate_hits=2,
        post_fall_lying_hits=2,
        min_quality=0.5,
    )
    machine = FallStateMachine(runtime)
    fall = {"fall": 0.9, "lying": 0.05, "walking": 0.01, "standing_still": 0.01}
    lying = {"fall": 0.1, "lying": 0.9, "walking": 0.01, "standing_still": 0.01}
    machine.update(0.0, fall, 1.0, "1")
    machine.update(0.5, fall, 1.0, "1")
    machine.update(1.0, lying, 1.0, "1")
    machine.update(1.5, lying, 1.0, "1")
    decision = machine.update(2.0, lying, 1.0, "1")
    assert decision.state == FallState.CONFIRMED.value

    health_config = HealthConfig(apnea_min_seconds=1.0, apnea_baseline_updates=1)
    respiratory = RespiratoryMonitor(health_config)
    estimates = [
        NodeRespirationEstimate(node, 15.0, 0.9, 1.0, 0.05, 0.1, 8, 1900)
        for node in (1, 2)
    ]
    respiratory.update(0.0, estimates, "lying", "1")
    apnea = respiratory.update(1.1, estimates, "lying", "1")
    assert apnea["apnea"]["suspected"]

    cough = CoughCandidateDetector(health_config)
    candidate = CoughCandidate(1, 2.0, (1, 2), 9.0)
    assert not cough.confirm(candidate, 0.99, "sneeze")
    assert cough.confirm(candidate, 0.99, "cough")
    assert cough.confirmed_cough_count == 1

    torch_result = "SKIPPED"
    try:
        import torch

        from .model import MultiNodeFallModel
        from .health_model import MultiNodeCoughModel

        model = MultiNodeFallModel(feature_channels=config.feature_channels)
        output = model(
            torch.zeros(2, config.max_nodes, config.feature_channels, config.window_frames),
            torch.tensor([[True, False, False, False], [True, True, False, False]]),
            torch.tensor([[1.0, 0.0, 0.0, 0.0], [1.0, 0.8, 0.0, 0.0]]),
        )
        assert output["activity_logits"].shape == (2, 10)
        assert output["count_logits"].shape == (2, 4)
        cough_model = MultiNodeCoughModel(feature_channels=config.feature_channels)
        cough_output = cough_model(
            torch.zeros(2, config.max_nodes, config.feature_channels, 64),
            torch.tensor([[True, True, False, False], [True, True, True, True]]),
            torch.tensor([[1.0, 0.8, 0.0, 0.0], [1.0, 0.9, 0.8, 0.7]]),
        )
        assert cough_output.shape == (2, 9)
        torch_result = (
            f"PASS fall_parameters={sum(p.numel() for p in model.parameters())} "
            f"cough_parameters={sum(p.numel() for p in cough_model.parameters())}"
        )
    except ImportError:
        pass
    print(
        f"PARSER=PASS FEATURES=PASS FALL_STATE=PASS RESPIRATORY=PASS "
        f"APNEA_GATE=PASS COUGH_GATE=PASS TORCH_MODELS={torch_result}"
    )
    print("RESULT=PASS_COMPLETE_SELFTEST")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

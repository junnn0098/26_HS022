"""One authoritative CSI feature pipeline shared by training and live use."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .config import FeatureConfig


@dataclass(frozen=True)
class WindowFeatures:
    features: np.ndarray  # (max_nodes, feature_channels, window_frames)
    node_mask: np.ndarray  # (max_nodes,)
    node_quality: np.ndarray  # (max_nodes,)


def _interpolate_columns(
    source_time: np.ndarray,
    source_values: np.ndarray,
    target_time: np.ndarray,
) -> np.ndarray:
    """Interpolate (samples, columns) data without a SciPy dependency."""
    order = np.argsort(source_time, kind="stable")
    source_time = source_time[order]
    source_values = source_values[order]
    source_time, unique_index = np.unique(source_time, return_index=True)
    source_values = source_values[unique_index]
    output = np.empty((target_time.size, source_values.shape[1]), dtype=np.float32)
    for column in range(source_values.shape[1]):
        output[:, column] = np.interp(
            target_time,
            source_time,
            source_values[:, column],
        )
    return output


def build_node_features(
    frame_time_ns: np.ndarray,
    iq: np.ndarray,
    rssi_dbm: np.ndarray,
    window_start_ns: int,
    config: FeatureConfig,
) -> tuple[np.ndarray, float]:
    """Build (feature_channels, time) features for one radio node."""
    if iq.ndim != 4 or iq.shape[-1] != 2:
        raise ValueError(f"iq must have shape (frames, antennas, subcarriers, 2), got {iq.shape}")
    if iq.shape[2] != config.subcarriers:
        raise ValueError(f"expected {config.subcarriers} subcarriers, got {iq.shape[2]}")
    if len(frame_time_ns) != len(iq) or len(rssi_dbm) != len(iq):
        raise ValueError("timestamp/IQ/RSSI lengths do not match")
    if len(iq) < 2:
        raise ValueError("at least two frames are required")

    target_seconds = np.arange(config.window_frames, dtype=np.float64) / config.sample_rate_hz
    source_seconds = (frame_time_ns.astype(np.float64) - float(window_start_ns)) / 1e9

    # Current hardware has one antenna. For future multi-antenna boards, average
    # I and Q separately so the feature shape remains stable.
    iq_float = iq.astype(np.float32).mean(axis=1)
    real = _interpolate_columns(source_seconds, iq_float[..., 0], target_seconds)
    imag = _interpolate_columns(source_seconds, iq_float[..., 1], target_seconds)
    complex_csi = real + 1j * imag

    log_amplitude = np.log1p(np.abs(complex_csi)).astype(np.float32)
    absolute_amplitude = np.clip((log_amplitude - 3.0) / 1.5, -3.0, 3.0)

    median = np.median(log_amplitude, axis=0, keepdims=True)
    mad = np.median(np.abs(log_amplitude - median), axis=0, keepdims=True)
    dynamic_amplitude = np.clip(
        (log_amplitude - median) / (1.4826 * mad + 0.05),
        -5.0,
        5.0,
    ).astype(np.float32)

    phase_delta = np.zeros_like(log_amplitude, dtype=np.float32)
    phase_delta[1:] = (
        np.angle(complex_csi[1:] * np.conj(complex_csi[:-1])) / np.pi
    ).astype(np.float32)

    rssi = _interpolate_columns(
        source_seconds,
        rssi_dbm.astype(np.float32).reshape(-1, 1),
        target_seconds,
    )
    rssi = np.clip((rssi + 70.0) / 20.0, -2.0, 2.0)

    features = np.concatenate(
        [
            absolute_amplitude.T,
            dynamic_amplitude.T,
            phase_delta.T,
            rssi.T,
        ],
        axis=0,
    ).astype(np.float32, copy=False)

    target_end = target_seconds[-1]
    source_min = float(source_seconds.min())
    source_max = float(source_seconds.max())
    covered = max(0.0, min(source_max, target_end) - max(source_min, 0.0))
    coverage = covered / max(target_end, 1e-9)
    density = min(1.0, len(iq) / max(config.window_frames, 1))
    quality = float(np.clip(coverage * density, 0.0, 1.0))
    return features, quality


def assemble_multinode_window(
    received_monotonic_ns: np.ndarray,
    node_id: np.ndarray,
    iq: np.ndarray,
    rssi_dbm: np.ndarray,
    expected_nodes: list[int] | tuple[int, ...],
    window_start_ns: int,
    config: FeatureConfig,
) -> WindowFeatures:
    """Build a fixed-size masked tensor from a variable number of nodes."""
    expected_nodes = sorted(set(int(node) for node in expected_nodes))
    if len(expected_nodes) > config.max_nodes:
        raise ValueError(
            f"capture contains {len(expected_nodes)} expected nodes, max_nodes={config.max_nodes}"
        )

    output = np.zeros(
        (config.max_nodes, config.feature_channels, config.window_frames),
        dtype=np.float32,
    )
    mask = np.zeros(config.max_nodes, dtype=np.bool_)
    quality = np.zeros(config.max_nodes, dtype=np.float32)
    window_end_ns = window_start_ns + int(config.window_seconds * 1e9)

    for slot, node in enumerate(expected_nodes):
        selected = (
            (node_id.astype(np.int64) == node)
            & (received_monotonic_ns >= window_start_ns - 100_000_000)
            & (received_monotonic_ns <= window_end_ns + 100_000_000)
        )
        if int(np.count_nonzero(selected)) < 2:
            continue
        node_features, node_quality = build_node_features(
            received_monotonic_ns[selected],
            iq[selected],
            rssi_dbm[selected],
            window_start_ns,
            config,
        )
        output[slot] = node_features
        quality[slot] = node_quality
        mask[slot] = node_quality >= config.min_node_quality

    return WindowFeatures(output, mask, quality)


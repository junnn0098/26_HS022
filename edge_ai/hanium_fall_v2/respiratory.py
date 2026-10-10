"""CSI-only dominant breathing-rate and conservative apnea-suspicion logic.

This module intentionally does not estimate heart rate.  It is designed for
wellness/research monitoring, not diagnosis.  Apnea is never inferred from a
missing node or poor RF quality: a reliable breathing baseline, low motion,
single-person occupancy, and multiple usable nodes are all required.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Iterable

import numpy as np

from .config import HealthConfig


@dataclass(frozen=True)
class NodeRespirationEstimate:
    node_id: int
    bpm: float
    confidence: float
    coverage: float
    motion_score: float
    recent_amplitude_ratio: float
    selected_components: int
    samples: int

    def to_dict(self) -> dict:
        payload = asdict(self)
        return {key: round(value, 6) if isinstance(value, float) else value for key, value in payload.items()}


def _interpolate(source_time: np.ndarray, values: np.ndarray, target_time: np.ndarray) -> np.ndarray:
    order = np.argsort(source_time, kind="stable")
    source_time = source_time[order]
    values = values[order]
    source_time, unique = np.unique(source_time, return_index=True)
    values = values[unique]
    output = np.empty((len(target_time), values.shape[1]), dtype=np.float64)
    for column in range(values.shape[1]):
        output[:, column] = np.interp(target_time, source_time, values[:, column])
    return output


def _linear_detrend(values: np.ndarray) -> np.ndarray:
    centered_time = np.arange(len(values), dtype=np.float64)
    centered_time -= centered_time.mean()
    centered_values = values - np.mean(values, axis=0, keepdims=True)
    denominator = float(np.dot(centered_time, centered_time)) + 1e-12
    slopes = centered_time @ centered_values / denominator
    return centered_values - centered_time[:, None] * slopes[None, :]


def _weighted_median(values: np.ndarray, weights: np.ndarray) -> float:
    order = np.argsort(values)
    ordered_values = values[order]
    ordered_weights = weights[order]
    cutoff = float(ordered_weights.sum()) * 0.5
    return float(ordered_values[np.searchsorted(np.cumsum(ordered_weights), cutoff)])


def estimate_node_respiration(
    node_id: int,
    frame_time_ns: np.ndarray,
    iq: np.ndarray,
    end_time_ns: int,
    config: HealthConfig,
) -> NodeRespirationEstimate | None:
    """Estimate the dominant respiration component for one node."""
    if iq.ndim != 4 or iq.shape[-1] != 2 or len(iq) != len(frame_time_ns):
        raise ValueError("respiration IQ must be (frames, antennas, subcarriers, 2)")
    if len(iq) < 8:
        return None

    window_seconds = float(config.respiratory_window_seconds)
    sample_rate = int(config.respiratory_sample_rate_hz)
    source_seconds = (frame_time_ns.astype(np.float64) - float(end_time_ns)) / 1e9
    selected = (source_seconds >= -window_seconds - 0.5) & (source_seconds <= 0.5)
    if int(np.count_nonzero(selected)) < 8:
        return None
    source_seconds = source_seconds[selected]
    iq = iq[selected]
    span = max(0.0, min(0.0, float(source_seconds.max())) - max(-window_seconds, float(source_seconds.min())))
    coverage = min(1.0, span / max(window_seconds, 1e-9))
    history_seconds = max(0.0, float(source_seconds.max() - source_seconds.min()))
    if history_seconds < config.respiratory_min_history_seconds:
        return None
    if float(source_seconds.max()) < -1.5:
        return None

    target_count = max(32, int(round(window_seconds * sample_rate)))
    target_seconds = np.arange(target_count, dtype=np.float64) / sample_rate - window_seconds
    iq_float = iq.astype(np.float64).mean(axis=1)
    real = _interpolate(source_seconds, iq_float[..., 0], target_seconds)
    imag = _interpolate(source_seconds, iq_float[..., 1], target_seconds)
    complex_csi = real + 1j * imag

    # The RC5 LLTF contract masks the first two complex values.  Exclude them
    # from spectral candidate selection rather than allowing zero columns to
    # dilute the estimate.
    usable = np.any(np.abs(complex_csi) > 0.0, axis=0)
    if int(np.count_nonzero(usable)) < 8:
        return None
    complex_csi = complex_csi[:, usable]
    log_amplitude = np.log1p(np.abs(complex_csi))
    amplitude_candidates = _linear_detrend(log_amplitude)

    # Adjacent-subcarrier phase difference suppresses most common phase drift
    # on a single-antenna ESP32 while retaining chest micro-motion signatures.
    adjacent_phase = np.angle(complex_csi[:, 1:] * np.conj(complex_csi[:, :-1]))
    adjacent_phase = np.unwrap(adjacent_phase, axis=0)
    phase_candidates = _linear_detrend(adjacent_phase)
    candidates = np.concatenate([amplitude_candidates, phase_candidates], axis=1)

    robust_scale = np.median(np.abs(candidates - np.median(candidates, axis=0)), axis=0)
    valid_columns = robust_scale > 1e-5
    if int(np.count_nonzero(valid_columns)) < 4:
        return None
    candidates = candidates[:, valid_columns]
    robust_scale = robust_scale[valid_columns]
    candidates = candidates / (1.4826 * robust_scale[None, :] + 1e-6)
    candidates = np.clip(candidates, -8.0, 8.0)

    taper = np.hanning(target_count)[:, None]
    spectrum = np.fft.rfft(candidates * taper, axis=0)
    frequencies = np.fft.rfftfreq(target_count, d=1.0 / sample_rate)
    power = np.abs(spectrum) ** 2
    breathing_band = (
        (frequencies >= config.respiratory_min_bpm / 60.0)
        & (frequencies <= config.respiratory_max_bpm / 60.0)
    )
    useful_band = (frequencies >= 0.05) & (frequencies <= min(3.0, sample_rate / 2.0))
    if int(np.count_nonzero(breathing_band)) < 2:
        return None
    band_power = np.sum(power[breathing_band], axis=0)
    total_power = np.sum(power[useful_band], axis=0) + 1e-9
    ratio = band_power / total_power
    band_values = power[breathing_band]
    peak = np.max(band_values, axis=0)
    floor = np.median(band_values, axis=0) + 1e-9
    prominence = np.clip(np.log1p(peak / floor) / 5.0, 0.0, 1.0)
    component_score = ratio * prominence
    top_count = min(8, int(np.count_nonzero(component_score > 0.015)))
    if top_count < 2:
        return None
    top = np.argsort(component_score)[-top_count:]

    filtered_spectrum = np.zeros_like(spectrum[:, top])
    filtered_spectrum[breathing_band] = spectrum[breathing_band][:, top]
    filtered = np.fft.irfft(filtered_spectrum, n=target_count, axis=0)
    selected_candidates = candidates[:, top].copy()
    reference = filtered[:, int(np.argmax(component_score[top]))]
    for column in range(filtered.shape[1]):
        if float(np.dot(reference, filtered[:, column])) < 0.0:
            filtered[:, column] *= -1.0
            selected_candidates[:, column] *= -1.0
    weights = component_score[top]
    weights = weights / max(float(weights.sum()), 1e-9)
    combined = filtered @ weights
    combined_raw = selected_candidates @ weights

    combined_spectrum = np.fft.rfft(combined * np.hanning(target_count))
    combined_power = np.abs(combined_spectrum) ** 2
    band_indices = np.flatnonzero(breathing_band)
    peak_index = int(band_indices[np.argmax(combined_power[breathing_band])])
    peak_frequency = float(frequencies[peak_index])
    # Quadratic interpolation reduces FFT-bin quantisation on the 60 s window.
    if 0 < peak_index < len(combined_power) - 1:
        left, center, right = (
            float(combined_power[peak_index - 1]),
            float(combined_power[peak_index]),
            float(combined_power[peak_index + 1]),
        )
        denominator = left - 2.0 * center + right
        if abs(denominator) > 1e-12:
            peak_frequency += 0.5 * (left - right) / denominator * (sample_rate / target_count)
    bpm = float(np.clip(peak_frequency * 60.0, config.respiratory_min_bpm, config.respiratory_max_bpm))

    band_total = float(np.sum(combined_power[breathing_band])) + 1e-9
    neighbourhood = combined_power[max(0, peak_index - 1) : peak_index + 2]
    concentration = float(np.clip(np.sum(neighbourhood) / band_total, 0.0, 1.0))
    component_quality = float(np.clip(np.mean(component_score[top]) / 0.35, 0.0, 1.0))
    confidence = float(np.clip(coverage * (0.35 + 0.65 * concentration) * component_quality, 0.0, 1.0))

    recent_count = max(8, int(round(config.apnea_recent_window_seconds * sample_rate)))
    recent_count = min(recent_count, target_count // 2)
    # Use the untapered selected components for amplitude comparison.  Using
    # the Hann-tapered inverse spectrum here would artificially suppress the
    # newest samples and create a false apnea candidate on every update.
    recent = _linear_detrend(combined_raw[-recent_count:, None])[:, 0]
    previous = combined_raw[-min(target_count, recent_count * 3) : -recent_count]
    previous = _linear_detrend(previous[:, None])[:, 0] if len(previous) else recent
    recent_rms = float(np.sqrt(np.mean(recent ** 2)))
    previous_rms = float(np.sqrt(np.mean(previous ** 2))) if len(previous) else recent_rms
    recent_ratio = float(np.clip(recent_rms / max(previous_rms, 1e-6), 0.0, 4.0))

    high_band = (frequencies >= 0.7) & (frequencies <= min(3.0, sample_rate / 2.0))
    high_power = float(np.sum(np.abs(np.fft.rfft(candidates.mean(axis=1) * np.hanning(target_count)))[high_band] ** 2))
    respiration_power = float(np.sum(combined_power[breathing_band]))
    motion_score = float(np.clip(high_power / (high_power + respiration_power + 1e-9), 0.0, 1.0))
    return NodeRespirationEstimate(
        node_id=int(node_id),
        bpm=bpm,
        confidence=confidence,
        coverage=coverage,
        motion_score=motion_score,
        recent_amplitude_ratio=recent_ratio,
        selected_components=top_count,
        samples=int(len(iq)),
    )


class RespiratoryMonitor:
    """Fuse node estimates and maintain a fail-safe apnea suspicion state."""

    def __init__(self, config: HealthConfig) -> None:
        self.config = config
        self.reliable_updates = 0
        self.apnea_candidate_since: float | None = None
        self.total_apnea_suspicions = 0
        self._last_apnea_state = "warming_up"

    def update(
        self,
        now_monotonic: float,
        estimates: Iterable[NodeRespirationEstimate],
        activity: str = "unknown",
        people_count: str | int | None = None,
    ) -> dict:
        estimates = list(estimates)
        minimum_coverage = min(
            0.95,
            self.config.respiratory_min_history_seconds
            / max(self.config.respiratory_window_seconds, 1e-9),
        )
        usable = [item for item in estimates if item.coverage >= minimum_coverage]
        weights = np.asarray([max(item.confidence, 0.02) for item in usable], dtype=np.float64)
        if usable:
            rates = np.asarray([item.bpm for item in usable], dtype=np.float64)
            fused_bpm = _weighted_median(rates, weights)
            disagreement = _weighted_median(np.abs(rates - fused_bpm), weights)
            agreement = float(np.exp(-disagreement / 3.0))
            confidence = float(np.clip(np.average([item.confidence for item in usable], weights=weights) * agreement, 0.0, 1.0))
            motion_score = float(np.median([item.motion_score for item in usable]))
            recent_ratio = float(np.median([item.recent_amplitude_ratio for item in usable]))
        else:
            fused_bpm = None
            confidence = 0.0
            motion_score = 1.0
            recent_ratio = 0.0

        reliable = (
            len(usable) >= self.config.respiratory_min_nodes
            and confidence >= self.config.respiratory_min_confidence
            and motion_score <= self.config.respiratory_max_motion_score
        )
        if reliable:
            self.reliable_updates += 1

        if people_count is None or str(people_count) in {"unknown", "unavailable", "None"}:
            people = self.config.assumed_people_when_model_unavailable
            occupancy_source = "configured_assumption"
        else:
            raw_people = str(people_count)
            people = 3 if raw_people == "3plus" else int(raw_people)
            occupancy_source = "activity_model"
        stationary = activity in {"unknown", "unavailable", "still", "sitting", "lying"}
        baseline_ready = self.reliable_updates >= self.config.apnea_baseline_updates
        apnea_eligible = (
            self.config.apnea_enabled
            and people == 1
            and stationary
            and len(usable) >= self.config.respiratory_min_nodes
            and motion_score <= self.config.respiratory_max_motion_score
            and baseline_ready
        )
        low_breathing_amplitude = recent_ratio <= self.config.apnea_amplitude_ratio

        if not self.config.apnea_enabled:
            apnea_state = "disabled"
            self.apnea_candidate_since = None
        elif people != 1:
            apnea_state = "not_applicable_multiple_people"
            self.apnea_candidate_since = None
        elif len(usable) < self.config.respiratory_min_nodes:
            apnea_state = "insufficient_signal"
            self.apnea_candidate_since = None
        elif not stationary or motion_score > self.config.respiratory_max_motion_score:
            apnea_state = "paused_motion"
            self.apnea_candidate_since = None
        elif not baseline_ready:
            apnea_state = "warming_up"
            self.apnea_candidate_since = None
        elif apnea_eligible and low_breathing_amplitude:
            if self.apnea_candidate_since is None:
                self.apnea_candidate_since = now_monotonic
            candidate_seconds = max(0.0, now_monotonic - self.apnea_candidate_since)
            apnea_state = "suspected" if candidate_seconds >= self.config.apnea_min_seconds else "candidate"
        else:
            apnea_state = "clear"
            self.apnea_candidate_since = None

        if apnea_state == "suspected" and self._last_apnea_state != "suspected":
            self.total_apnea_suspicions += 1
        self._last_apnea_state = apnea_state
        candidate_seconds = (
            max(0.0, now_monotonic - self.apnea_candidate_since)
            if self.apnea_candidate_since is not None
            else 0.0
        )
        return {
            "breathing_rate_bpm": round(float(fused_bpm), 3) if reliable and fused_bpm is not None else None,
            "breathing_confidence": round(confidence, 6),
            "breathing_status": "reliable" if reliable else ("warming_up" if not baseline_ready else "unreliable"),
            "dominant_person_only": True,
            "motion_score": round(motion_score, 6),
            "recent_breath_amplitude_ratio": round(recent_ratio, 6),
            "usable_nodes": len(usable),
            "occupancy_assumption": people,
            "occupancy_source": occupancy_source,
            "apnea": {
                "state": apnea_state,
                "suspected": apnea_state == "suspected",
                "candidate_seconds": round(candidate_seconds, 3),
                "threshold_seconds": self.config.apnea_min_seconds,
                "total_suspicions": self.total_apnea_suspicions,
                "safety_label": "research_only_not_medical_diagnosis",
            },
            "nodes": [item.to_dict() for item in estimates],
        }

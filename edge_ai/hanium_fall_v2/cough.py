"""Multi-node CSI burst detector used to propose cough-like events.

CSI alone cannot prove that a burst was acoustically a cough.  Therefore this
detector exposes candidate counts separately from classifier-confirmed coughs.
The confirmed counter is advanced only by an optional trained cough model.
"""

from __future__ import annotations

from collections import defaultdict, deque
from dataclasses import dataclass

import numpy as np

from .config import HealthConfig


@dataclass(frozen=True)
class CoughCandidate:
    event_id: int
    monotonic_seconds: float
    nodes: tuple[int, ...]
    peak_z: float
    classification: str = "cough_like_unverified"

    def to_dict(self) -> dict:
        return {
            "event_id": self.event_id,
            "monotonic_seconds": round(self.monotonic_seconds, 6),
            "nodes": list(self.nodes),
            "peak_z": round(self.peak_z, 4),
            "classification": self.classification,
        }


class CoughCandidateDetector:
    def __init__(self, config: HealthConfig) -> None:
        self.config = config
        self.previous_amplitude: dict[int, np.ndarray] = {}
        self.baselines: defaultdict[int, deque[tuple[float, float]]] = defaultdict(deque)
        self.recent_spikes: deque[tuple[float, int, float]] = deque()
        self.last_candidate_time = float("-inf")
        self.candidate_count = 0
        self.confirmed_cough_count = 0
        self.last_candidate: CoughCandidate | None = None
        self.last_confirmed: dict | None = None

    @staticmethod
    def _amplitude(iq: np.ndarray) -> np.ndarray:
        if iq.ndim != 3 or iq.shape[-1] != 2:
            raise ValueError("cough IQ frame must be (antennas, subcarriers, 2)")
        iq_float = iq.astype(np.float32).mean(axis=0)
        amplitude = np.log1p(np.hypot(iq_float[:, 0], iq_float[:, 1]))
        usable = amplitude > 0.0
        return amplitude[usable]

    def add_frame(self, node_id: int, now: float, iq: np.ndarray) -> CoughCandidate | None:
        if not self.config.cough_enabled:
            return None
        amplitude = self._amplitude(iq)
        previous = self.previous_amplitude.get(int(node_id))
        self.previous_amplitude[int(node_id)] = amplitude
        if previous is None or len(previous) != len(amplitude) or len(amplitude) < 8:
            return None
        # Median across subcarriers is robust to isolated quantisation glitches.
        energy = float(np.median(np.abs(amplitude - previous)))
        history = self.baselines[int(node_id)]
        cutoff = now - self.config.cough_baseline_seconds
        while history and history[0][0] < cutoff:
            history.popleft()

        z_score = 0.0
        if len(history) >= self.config.cough_min_baseline_samples:
            baseline = np.asarray([item[1] for item in history], dtype=np.float64)
            center = float(np.median(baseline))
            mad = float(np.median(np.abs(baseline - center)))
            scale = max(1.4826 * mad, center * 0.08, 1e-4)
            z_score = max(0.0, (energy - center) / scale)

        # Do not teach a large transient into the slowly moving baseline.
        if z_score < 3.0:
            history.append((now, energy))
        if z_score < self.config.cough_candidate_z:
            return None

        self.recent_spikes.append((now, int(node_id), z_score))
        coincidence_start = now - self.config.cough_coincidence_seconds
        while self.recent_spikes and self.recent_spikes[0][0] < coincidence_start:
            self.recent_spikes.popleft()
        strongest_by_node: dict[int, float] = {}
        for _timestamp, spike_node, spike_z in self.recent_spikes:
            strongest_by_node[spike_node] = max(strongest_by_node.get(spike_node, 0.0), spike_z)
        if len(strongest_by_node) < self.config.cough_candidate_min_nodes:
            return None
        if now - self.last_candidate_time < self.config.cough_refractory_seconds:
            return None

        self.candidate_count += 1
        self.last_candidate_time = now
        candidate = CoughCandidate(
            event_id=self.candidate_count,
            monotonic_seconds=now,
            nodes=tuple(sorted(strongest_by_node)),
            peak_z=max(strongest_by_node.values()),
        )
        self.last_candidate = candidate
        self.recent_spikes.clear()
        return candidate

    def confirm(self, candidate: CoughCandidate, probability: float, label: str) -> bool:
        confirmed = label == "cough" and probability >= self.config.cough_confirm_probability
        if confirmed:
            self.confirmed_cough_count += 1
            self.last_confirmed = {
                **candidate.to_dict(),
                "classification": "cough",
                "probability": round(float(probability), 6),
            }
        return confirmed

    def status(self, classifier_available: bool) -> dict:
        return {
            "confirmed_cough_count": self.confirmed_cough_count if classifier_available else None,
            "cough_like_candidate_count": self.candidate_count,
            "classifier_available": classifier_available,
            "mode": "trained_classifier" if classifier_available else "candidate_only_unvalidated",
            "last_candidate": self.last_candidate.to_dict() if self.last_candidate else None,
            "last_confirmed": self.last_confirmed,
        }


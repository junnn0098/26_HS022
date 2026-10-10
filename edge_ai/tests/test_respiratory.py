import unittest

import numpy as np

from hanium_fall_v2.config import HealthConfig
from hanium_fall_v2.respiratory import (
    NodeRespirationEstimate,
    RespiratoryMonitor,
    estimate_node_respiration,
)


class RespiratoryTests(unittest.TestCase):
    def test_synthetic_fifteen_bpm_is_recovered(self):
        config = HealthConfig()
        sample_rate = 32
        seconds = 61
        time_s = np.arange(sample_rate * seconds, dtype=np.float64) / sample_rate
        timestamps = (time_s * 1e9).astype(np.int64)
        iq = np.zeros((len(time_s), 1, 64, 2), dtype=np.int8)
        generator = np.random.default_rng(7)
        for subcarrier in range(2, 64):
            phase = 0.02 * subcarrier
            real = (
                35.0
                + 7.0 * np.sin(2.0 * np.pi * 0.25 * time_s + phase)
                + generator.normal(0.0, 0.7, len(time_s))
            )
            imag = 8.0 + 2.0 * np.sin(2.0 * np.pi * 0.25 * time_s + phase)
            iq[:, 0, subcarrier, 0] = np.rint(real).astype(np.int8)
            iq[:, 0, subcarrier, 1] = np.rint(imag).astype(np.int8)
        estimate = estimate_node_respiration(
            1,
            timestamps,
            iq,
            int(timestamps[-1]),
            config,
        )
        self.assertIsNotNone(estimate)
        self.assertAlmostEqual(estimate.bpm, 15.0, delta=0.75)
        self.assertGreater(estimate.confidence, 0.70)
        self.assertGreater(estimate.recent_amplitude_ratio, 0.70)

    @staticmethod
    def estimate(node_id, ratio=1.0):
        return NodeRespirationEstimate(
            node_id=node_id,
            bpm=15.0,
            confidence=0.90,
            coverage=1.0,
            motion_score=0.05,
            recent_amplitude_ratio=ratio,
            selected_components=8,
            samples=1900,
        )

    def test_apnea_requires_baseline_two_nodes_and_time(self):
        config = HealthConfig(apnea_min_seconds=10.0, apnea_baseline_updates=3)
        monitor = RespiratoryMonitor(config)
        normal = [self.estimate(1), self.estimate(2)]
        for now in (0.0, 2.0, 4.0):
            status = monitor.update(now, normal, "lying", "1")
        self.assertEqual(status["apnea"]["state"], "clear")
        low = [self.estimate(1, 0.10), self.estimate(2, 0.12)]
        self.assertEqual(monitor.update(6.0, low, "lying", "1")["apnea"]["state"], "candidate")
        status = monitor.update(16.1, low, "lying", "1")
        self.assertTrue(status["apnea"]["suspected"])
        self.assertEqual(status["apnea"]["total_suspicions"], 1)

    def test_multiple_people_blocks_apnea_suspicion(self):
        config = HealthConfig(apnea_min_seconds=1.0, apnea_baseline_updates=1)
        monitor = RespiratoryMonitor(config)
        low = [self.estimate(1, 0.05), self.estimate(2, 0.05)]
        monitor.update(0.0, low, "lying", "2")
        status = monitor.update(5.0, low, "lying", "2")
        self.assertEqual(status["apnea"]["state"], "not_applicable_multiple_people")
        self.assertFalse(status["apnea"]["suspected"])


if __name__ == "__main__":
    unittest.main()

import unittest
from dataclasses import replace

import numpy as np

from hanium_fall_v2.config import HealthConfig
from hanium_fall_v2.cough import CoughCandidateDetector


class CoughDetectorTests(unittest.TestCase):
    @staticmethod
    def frame(level: float, wobble: float = 0.0) -> np.ndarray:
        values = np.zeros((1, 64, 2), dtype=np.int8)
        carrier = np.arange(64, dtype=np.float32)
        values[0, 2:, 0] = np.rint(level + wobble * np.sin(carrier[2:])).astype(np.int8)
        values[0, 2:, 1] = 5
        return values

    def test_requires_coincident_spikes_from_two_nodes(self):
        config = replace(
            HealthConfig(),
            cough_candidate_z=4.0,
            cough_min_baseline_samples=10,
            cough_candidate_min_nodes=2,
        )
        detector = CoughCandidateDetector(config)
        now = 0.0
        for index in range(30):
            detector.add_frame(1, now, self.frame(30.0, 0.7))
            detector.add_frame(2, now + 0.005, self.frame(31.0, 0.8))
            now += 0.05

        self.assertIsNone(detector.add_frame(1, now, self.frame(65.0, 3.0)))
        candidate = detector.add_frame(2, now + 0.08, self.frame(66.0, 3.0))
        self.assertIsNotNone(candidate)
        self.assertEqual(candidate.nodes, (1, 2))
        self.assertEqual(detector.status(False)["confirmed_cough_count"], None)
        self.assertEqual(detector.status(False)["cough_like_candidate_count"], 1)

    def test_only_trained_classifier_confirmation_counts_as_cough(self):
        config = replace(HealthConfig(), cough_confirm_probability=0.8)
        detector = CoughCandidateDetector(config)
        from hanium_fall_v2.cough import CoughCandidate

        candidate = CoughCandidate(1, 10.0, (1, 2), 8.0)
        self.assertFalse(detector.confirm(candidate, 0.99, "sneeze"))
        self.assertFalse(detector.confirm(candidate, 0.70, "cough"))
        self.assertTrue(detector.confirm(candidate, 0.91, "cough"))
        self.assertEqual(detector.status(True)["confirmed_cough_count"], 1)


if __name__ == "__main__":
    unittest.main()

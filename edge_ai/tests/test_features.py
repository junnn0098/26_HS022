import unittest

import numpy as np

from hanium_fall_v2.config import FeatureConfig
from hanium_fall_v2.features import assemble_multinode_window, build_node_features


class FeatureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = FeatureConfig()
        self.frames = 165
        self.timestamps = np.arange(self.frames, dtype=np.int64) * int(1e9 / 33)
        base = np.zeros((self.frames, 1, 64, 2), dtype=np.int8)
        base[..., 0] = 3
        base[..., 1] = 4
        self.iq = base
        self.rssi = np.full(self.frames, -60, dtype=np.int8)

    def test_node_feature_shape_and_quality(self) -> None:
        features, quality = build_node_features(
            self.timestamps, self.iq, self.rssi, 0, self.config
        )
        self.assertEqual(features.shape, (193, 160))
        self.assertTrue(np.isfinite(features).all())
        self.assertGreater(quality, 0.95)

    def test_variable_node_mask(self) -> None:
        window = assemble_multinode_window(
            self.timestamps,
            np.ones(self.frames, dtype=np.uint8),
            self.iq,
            self.rssi,
            [1, 2],
            0,
            self.config,
        )
        self.assertEqual(window.features.shape, (4, 193, 160))
        self.assertEqual(window.node_mask.tolist(), [True, False, False, False])


if __name__ == "__main__":
    unittest.main()

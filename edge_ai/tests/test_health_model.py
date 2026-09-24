import unittest


class HealthModelTests(unittest.TestCase):
    def test_variable_node_cough_forward(self):
        try:
            import torch
        except ImportError:
            self.skipTest("torch not installed")
        from hanium_fall_v2.config import FeatureConfig
        from hanium_fall_v2.health_model import MultiNodeCoughModel

        config = FeatureConfig(window_seconds=2.0)
        model = MultiNodeCoughModel(feature_channels=config.feature_channels)
        logits = model(
            torch.zeros(2, config.max_nodes, config.feature_channels, config.window_frames),
            torch.tensor([[True, True, False, False], [True, True, True, True]]),
            torch.tensor([[1.0, 0.8, 0.0, 0.0], [1.0, 0.9, 0.8, 0.7]]),
        )
        self.assertEqual(tuple(logits.shape), (2, 9))


if __name__ == "__main__":
    unittest.main()

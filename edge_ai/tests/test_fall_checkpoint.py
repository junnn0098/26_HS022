import importlib.util
import unittest


TORCH_AVAILABLE = importlib.util.find_spec("torch") is not None


@unittest.skipUnless(TORCH_AVAILABLE, "PyTorch is tested on the Jetson target")
class FallCheckpointTests(unittest.TestCase):
    def setUp(self) -> None:
        import torch

        from hanium_fall_v2.fall_checkpoint import (
            CHECKPOINT_SCHEMA,
            EXPECTED_FEATURE_CONFIG,
            EXPECTED_MODEL_CONFIG,
        )
        from hanium_fall_v2.labels import ACTIVITIES
        from hanium_fall_v2.model import MultiNodeFallModel

        self.torch = torch
        self.payload = {
            "schema": CHECKPOINT_SCHEMA,
            "model_state_dict": MultiNodeFallModel(**EXPECTED_MODEL_CONFIG).state_dict(),
            "model_config": dict(EXPECTED_MODEL_CONFIG),
            "feature_config": dict(EXPECTED_FEATURE_CONFIG),
            "activity_labels": list(ACTIVITIES),
            "count_labels": ["0", "1", "2", "3plus"],
        }

    def test_canonical_checkpoint_is_live_ready(self) -> None:
        from hanium_fall_v2.fall_checkpoint import validate_fall_checkpoint_payload

        report = validate_fall_checkpoint_payload(self.payload, self.torch)
        self.assertEqual(report["result"], "PASS_FALL_CHECKPOINT_LIVE_READY")
        self.assertTrue(report["weights_compatible"])
        self.assertTrue(report["live_ready"])
        self.assertTrue(report["mask_aware_smoke_test"])

    def test_external_raw_state_dict_needs_metadata(self) -> None:
        from hanium_fall_v2.fall_checkpoint import validate_fall_checkpoint_payload

        report = validate_fall_checkpoint_payload(
            self.payload["model_state_dict"], self.torch
        )
        self.assertEqual(report["result"], "PASS_WEIGHTS_COMPATIBLE_METADATA_REQUIRED")
        self.assertTrue(report["weights_compatible"])
        self.assertFalse(report["live_ready"])

    def test_wrong_feature_contract_is_rejected(self) -> None:
        from hanium_fall_v2.fall_checkpoint import validate_fall_checkpoint_payload

        self.payload["feature_config"]["subcarriers"] = 192
        self.payload["feature_config"]["feature_channels"] = 577
        report = validate_fall_checkpoint_payload(self.payload, self.torch)
        self.assertTrue(report["weights_compatible"])
        self.assertFalse(report["live_ready"])
        self.assertTrue(any("subcarriers" in error for error in report["errors"]))

    def test_dataparallel_prefix_is_accepted(self) -> None:
        from hanium_fall_v2.fall_checkpoint import validate_fall_checkpoint_payload

        self.payload["model_state_dict"] = {
            "module." + key: value
            for key, value in self.payload["model_state_dict"].items()
        }
        report = validate_fall_checkpoint_payload(self.payload, self.torch)
        self.assertTrue(report["live_ready"])


if __name__ == "__main__":
    unittest.main()

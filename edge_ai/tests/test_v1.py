import importlib.util
import struct
import unittest
from pathlib import Path

import numpy as np

from hanium_fall_v1.data import CHANNEL_SETS, LLTF_CHANNELS, NON_CSI_CHANNELS, load_windows, preprocess
from hanium_fall_v1.metrics import auroc, binary_metrics

TORCH_AVAILABLE = importlib.util.find_spec("torch") is not None
if TORCH_AVAILABLE:  # these modules import the model, which needs PyTorch
    from hanium_fall_v1.realtime_inference import AlertGate, packet_to_frame, packet_width
    from hanium_fall_v1.train import split_recordings, split_temporal
SAMPLE = Path(__file__).resolve().parents[2] / "dataset" / "sample"


class PreprocessTests(unittest.TestCase):
    def test_team_zscore_uses_the_whole_window(self) -> None:
        window = np.random.default_rng(0).normal(5.0, 2.0, (500, 134)).astype(np.float32)
        x = preprocess(window, "all")
        self.assertEqual(x.shape, (134, 500))
        self.assertAlmostEqual(float(x.mean()), 0.0, places=4)
        self.assertAlmostEqual(float(x.std()), 1.0, places=3)

    def test_channel_sets_zero_everything_else(self) -> None:
        window = np.random.default_rng(1).normal(size=(2, 500, 134)).astype(np.float32)
        x = preprocess(window, "lltf")
        outside = [c for c in range(134) if c not in LLTF_CHANNELS]
        self.assertTrue(np.all(x[:, outside] == 0))
        self.assertEqual(len(CHANNEL_SETS["csi"]) + len(NON_CSI_CHANNELS), 134)


@unittest.skipUnless(TORCH_AVAILABLE, "PyTorch is required by the realtime module")
class PacketTests(unittest.TestCase):
    def test_frame_matches_training_layout(self) -> None:
        # RuView payload after the 8-byte prefix: frequency(4) sequence(4) rssi noise ppdu flags, then I/Q.
        header = struct.pack("<IIbbBB", 2437, 0x0102, -44, -98, 0, 0x10)
        iq = bytes([3, 4] * 128)
        packet = struct.pack("<IBBH", 0xC5110001, 2, 1, 128) + header + iq
        frame = packet_to_frame(packet)
        self.assertEqual(packet_width(packet), 134)
        self.assertEqual(frame[0], 0.0)  # high bytes of 2437 MHz
        self.assertAlmostEqual(float(frame[1]), float(np.hypot(2, 1)), places=5)  # sequence bytes, not CSI
        self.assertEqual(frame[4], 16.0)  # ppdu, flags
        self.assertAlmostEqual(float(frame[5]), 5.0)  # first I/Q pair
        self.assertEqual(frame[133], 0.0)  # past the end of a 134-wide packet

    def test_alert_gate(self) -> None:
        gate = AlertGate()
        self.assertEqual(gate.update(0.95), "immediate")
        self.assertIsNone(gate.update(0.6))
        self.assertEqual(gate.update(0.6), "confirmed")
        self.assertIsNone(gate.update(0.2))


@unittest.skipUnless(TORCH_AVAILABLE, "PyTorch is required by the training module")
class SplitTests(unittest.TestCase):
    rows = [
        {"recording": f"r{i}", "label": label, "category": category, "batch": batch, "is_fall": int(label == "fall")}
        for i, (label, category, batch) in enumerate(
            [("fall", "fall", "b1_0708_0709"), ("walking", "daily", "b1_0708_0709"),
             ("fall", "fall", "b2_0715"), ("sitting", "daily", "b3_0724"),
             ("fall", "fall", "b4_0728"), ("stumble_no_fall", "confusing", "b4_0728")])
        for _ in range(3)
    ]

    def test_recording_split_never_shares_a_recording(self) -> None:
        for train, test in split_recordings(self.rows, 3, seed=0):
            train_recordings = {self.rows[i]["recording"] for i in train}
            test_recordings = {self.rows[i]["recording"] for i in test}
            self.assertFalse(train_recordings & test_recordings)
            self.assertTrue(test_recordings)

    def test_temporal_split_tests_on_later_days(self) -> None:
        (train, test), = split_temporal(self.rows)
        self.assertEqual({self.rows[i]["batch"] for i in test}, {"b3_0724", "b4_0728"})
        self.assertNotIn("b3_0724", {self.rows[i]["batch"] for i in train})



class MetricTests(unittest.TestCase):
    def test_metrics(self) -> None:
        result = binary_metrics(np.array([1, 1, 0, 0]), np.array([0.9, 0.4, 0.6, 0.1]))
        self.assertEqual((result["tp"], result["fn"], result["fp"], result["tn"]), (1, 1, 1, 1))
        self.assertAlmostEqual(auroc(np.array([0, 0, 1, 1]), np.array([0.1, 0.4, 0.35, 0.8])), 0.75)


@unittest.skipUnless(TORCH_AVAILABLE, "PyTorch is required for the model tests")
class ModelTests(unittest.TestCase):
    def test_parameter_count_and_shape(self) -> None:
        import torch

        from hanium_fall_v1.model import CSI1DCNN, parameter_count

        model = CSI1DCNN()
        self.assertEqual(parameter_count(model), 65_762)
        self.assertEqual(tuple(model(torch.zeros(3, 134, 500)).shape), (3, 2))

    def test_team_weights_on_repository_sample(self) -> None:
        import torch

        from hanium_fall_v1.model import FALL_INDEX, CSI1DCNN

        windows, rows = load_windows(SAMPLE, SAMPLE / "sample_windows.csv")
        weights = Path(__file__).resolve().parents[1] / "hanium_fall_v1" / "weights"
        for name in ("team_v1_0717.pth", "team_v1_0803.pth"):
            model = CSI1DCNN()
            model.load_state_dict(torch.load(weights / name, map_location="cpu", weights_only=True))
            model.eval()
            with torch.no_grad():
                probability = torch.softmax(model(torch.from_numpy(preprocess(windows, "all"))), 1)[:, FALL_INDEX]
            self.assertEqual(len(probability), len(rows))
            self.assertTrue(bool(((probability >= 0) & (probability <= 1)).all()))


if __name__ == "__main__":
    unittest.main()

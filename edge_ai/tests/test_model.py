import importlib.util
import unittest


TORCH_AVAILABLE = importlib.util.find_spec("torch") is not None


@unittest.skipUnless(TORCH_AVAILABLE, "PyTorch is tested on the Jetson target")
class ModelTests(unittest.TestCase):
    def test_variable_node_forward(self) -> None:
        import torch

        from hanium_fall_v2.model import MultiNodeFallModel

        model = MultiNodeFallModel()
        output = model(
            torch.zeros(2, 4, 193, 160),
            torch.tensor([[True, False, False, False], [True, True, False, False]]),
            torch.tensor([[1.0, 0.0, 0.0, 0.0], [1.0, 0.8, 0.0, 0.0]]),
        )
        self.assertEqual(tuple(output["activity_logits"].shape), (2, 10))
        self.assertEqual(tuple(output["count_logits"].shape), (2, 4))
        self.assertEqual(tuple(output["quality"].shape), (2,))
        torch.testing.assert_close(output["node_attention"].sum(1), torch.ones(2))


if __name__ == "__main__":
    unittest.main()

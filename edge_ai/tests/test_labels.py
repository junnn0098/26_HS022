import unittest

from hanium_fall_v2.labels import display_activity


class LabelTests(unittest.TestCase):
    def test_training_labels_collapse_to_user_states(self):
        self.assertEqual(display_activity("standing_still"), "still")
        self.assertEqual(display_activity("stand_up"), "still")
        self.assertEqual(display_activity("sit_down"), "sitting")
        self.assertEqual(display_activity("lie_down"), "lying")
        self.assertEqual(display_activity("fall"), "fall")


if __name__ == "__main__":
    unittest.main()

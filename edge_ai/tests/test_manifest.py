import unittest

from hanium_fall_v2.build_manifest import assign_group_splits, connected_subject_groups


class ManifestTests(unittest.TestCase):
    def test_groups_never_cross_splits(self) -> None:
        groups = [f"person{index:02d}" for index in range(10)]
        result = assign_group_splits(groups, 123)
        self.assertEqual(set(result), set(groups))
        self.assertEqual(set(result.values()), {"train", "val", "test"})

    def test_fewer_than_three_groups_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "at least three"):
            assign_group_splits(["person01", "person02"], 123)

    def test_overlapping_multi_person_sessions_share_group(self) -> None:
        sessions = [
            {"activity": "walking", "participants": ["p01", "p02"]},
            {"activity": "sitting", "participants": ["p02", "p03"]},
            {"activity": "walking", "participants": ["p04", "p05"]},
            {"activity": "empty", "participants": []},
        ]
        groups = connected_subject_groups(sessions)
        self.assertEqual(groups[0], groups[1])
        self.assertNotEqual(groups[0], groups[2])
        self.assertIsNone(groups[3])


if __name__ == "__main__":
    unittest.main()

import unittest

from hanium_fall_v2.config import RuntimeConfig
from hanium_fall_v2.fall_state import FallStateMachine


class FallStateTests(unittest.TestCase):
    def test_single_spike_does_not_alarm(self) -> None:
        machine = FallStateMachine(RuntimeConfig(fall_candidate_hits=2))
        decision = machine.update(0.0, {"fall": 0.95}, 1.0, "1")
        self.assertFalse(decision.alarm)
        decision = machine.update(0.5, {"fall": 0.05, "walking": 0.9}, 1.0, "1")
        self.assertEqual(decision.state, "normal")

    def test_repeated_fall_then_lying_confirms(self) -> None:
        config = RuntimeConfig(fall_candidate_hits=2, post_fall_lying_hits=2)
        machine = FallStateMachine(config)
        fall = {"fall": 0.9, "lying": 0.0}
        lying = {"fall": 0.1, "lying": 0.9}
        machine.update(0.0, fall, 1.0, "1")
        machine.update(0.5, fall, 1.0, "1")
        machine.update(1.0, lying, 1.0, "1")
        machine.update(1.5, lying, 1.0, "1")
        decision = machine.update(2.0, lying, 1.0, "1")
        self.assertTrue(decision.alarm)
        self.assertEqual(decision.state, "confirmed")

    def test_empty_room_clears_candidate(self) -> None:
        machine = FallStateMachine(RuntimeConfig(fall_candidate_hits=1))
        machine.update(0.0, {"fall": 0.9}, 1.0, "1")
        decision = machine.update(0.5, {"fall": 0.9}, 1.0, "0")
        self.assertEqual(decision.state, "normal")

    def test_confirmed_alarm_is_latched_before_recovery(self) -> None:
        config = RuntimeConfig(
            fall_candidate_hits=1,
            post_fall_lying_hits=1,
            recovery_hits=1,
            confirmed_hold_seconds=30.0,
        )
        machine = FallStateMachine(config)
        machine.update(0.0, {"fall": 0.9}, 1.0, "1")
        machine.update(0.5, {"lying": 0.9}, 1.0, "1")
        confirmed = machine.update(1.0, {"lying": 0.9}, 1.0, "1")
        self.assertTrue(confirmed.alarm)
        held = machine.update(2.0, {"walking": 0.9}, 1.0, "1")
        self.assertTrue(held.alarm)
        self.assertEqual(held.reason, "alarm_latched")
        recovered = machine.update(31.1, {"walking": 0.9}, 1.0, "1")
        self.assertEqual(recovered.state, "recovered")


if __name__ == "__main__":
    unittest.main()

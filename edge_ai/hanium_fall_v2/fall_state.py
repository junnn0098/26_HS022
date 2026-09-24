"""Temporal fall confirmation state machine that suppresses single-window alarms."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from enum import Enum

from .config import RuntimeConfig


class FallState(str, Enum):
    NORMAL = "normal"
    FALL_CANDIDATE = "fall_candidate"
    POST_FALL_CHECK = "post_fall_check"
    CONFIRMED = "confirmed"
    RECOVERED = "recovered"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class FallDecision:
    state: str
    previous_state: str
    changed: bool
    alarm: bool
    reason: str
    candidate_hits: int
    lying_hits: int
    recovery_hits: int

    def to_dict(self) -> dict:
        return asdict(self)


class FallStateMachine:
    def __init__(self, config: RuntimeConfig | None = None) -> None:
        self.config = config or RuntimeConfig()
        self.state = FallState.NORMAL
        self.state_started = 0.0
        self.candidate_hits = 0
        self.lying_hits = 0
        self.recovery_hits = 0

    def _transition(self, state: FallState, now: float) -> FallState:
        previous = self.state
        self.state = state
        self.state_started = now
        if state in (FallState.NORMAL, FallState.RECOVERED):
            self.candidate_hits = 0
            self.lying_hits = 0
        if state == FallState.NORMAL:
            self.recovery_hits = 0
        return previous

    def update(
        self,
        now: float,
        activity_probabilities: dict[str, float],
        quality: float,
        people_count_label: str,
    ) -> FallDecision:
        previous = self.state
        reason = "stable"
        fall_probability = float(activity_probabilities.get("fall", 0.0))
        lying_probability = float(activity_probabilities.get("lying", 0.0))
        recovery_probability = max(
            float(activity_probabilities.get("walking", 0.0)),
            float(activity_probabilities.get("standing_still", 0.0)),
            float(activity_probabilities.get("stand_up", 0.0)),
        )

        if quality < self.config.min_quality:
            if self.state not in (FallState.CONFIRMED, FallState.POST_FALL_CHECK):
                self._transition(FallState.UNKNOWN, now)
            reason = "low_quality"
        elif people_count_label == "0":
            self._transition(FallState.NORMAL, now)
            reason = "room_empty"
        elif self.state == FallState.UNKNOWN:
            self._transition(FallState.NORMAL, now)
            reason = "quality_recovered"
        elif self.state == FallState.NORMAL:
            if fall_probability >= self.config.fall_candidate_probability:
                self.candidate_hits += 1
            else:
                self.candidate_hits = max(0, self.candidate_hits - 1)
            if self.candidate_hits >= self.config.fall_candidate_hits:
                self._transition(FallState.FALL_CANDIDATE, now)
                reason = "repeated_fall_probability"
        elif self.state == FallState.FALL_CANDIDATE:
            self._transition(FallState.POST_FALL_CHECK, now)
            reason = "checking_post_fall_posture"
        elif self.state == FallState.POST_FALL_CHECK:
            if lying_probability >= self.config.post_fall_lying_probability:
                self.lying_hits += 1
            if recovery_probability >= self.config.recovery_probability:
                self.recovery_hits += 1
            else:
                self.recovery_hits = max(0, self.recovery_hits - 1)
            if self.recovery_hits >= self.config.recovery_hits:
                self._transition(FallState.RECOVERED, now)
                reason = "person_recovered"
            elif self.lying_hits >= self.config.post_fall_lying_hits:
                self._transition(FallState.CONFIRMED, now)
                reason = "fall_then_lying_confirmed"
            elif now - self.state_started >= self.config.post_fall_timeout_seconds:
                self._transition(FallState.NORMAL, now)
                reason = "post_fall_not_confirmed"
        elif self.state == FallState.CONFIRMED:
            if now - self.state_started < self.config.confirmed_hold_seconds:
                self.recovery_hits = 0
                reason = "alarm_latched"
            else:
                if recovery_probability >= self.config.recovery_probability:
                    self.recovery_hits += 1
                else:
                    self.recovery_hits = 0
                if self.recovery_hits >= self.config.recovery_hits:
                    self._transition(FallState.RECOVERED, now)
                    reason = "confirmed_person_recovered"
        elif self.state == FallState.RECOVERED:
            if now - self.state_started >= 2.0:
                self._transition(FallState.NORMAL, now)
                reason = "recovery_complete"

        changed = self.state != previous
        return FallDecision(
            state=self.state.value,
            previous_state=previous.value,
            changed=changed,
            alarm=self.state == FallState.CONFIRMED,
            reason=reason,
            candidate_hits=self.candidate_hits,
            lying_hits=self.lying_hits,
            recovery_hits=self.recovery_hits,
        )

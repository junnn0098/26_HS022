"""Canonical room-level labels for data collection and training."""

from __future__ import annotations


ACTIVITIES = (
    "empty",
    "standing_still",
    "walking",
    "sit_down",
    "sitting",
    "lie_down",
    "lying",
    "stand_up",
    "fall",
    "other_motion",
)

EVENT_ACTIVITIES = ("sit_down", "lie_down", "stand_up", "fall")

STEADY_OUTPUT_MAP = {
    "empty": "empty",
    "standing_still": "still",
    "walking": "walking",
    "sit_down": "sitting",
    "sitting": "sitting",
    "lie_down": "lying",
    "lying": "lying",
    "stand_up": "still",
    "fall": "fall",
    "other_motion": "other_motion",
}

DISPLAY_ACTIVITIES = (
    "empty",
    "still",
    "walking",
    "sitting",
    "lying",
    "fall",
    "other_motion",
)


def display_activity(activity: str) -> str:
    """Collapse the training taxonomy into the stable user-facing taxonomy."""
    try:
        return STEADY_OUTPUT_MAP[activity]
    except KeyError as exc:
        raise ValueError(f"unknown activity: {activity}") from exc


def people_bucket(people: int) -> str:
    if people < 0:
        raise ValueError("people must be non-negative")
    return str(people) if people < 3 else "3plus"


def validate_label(activity: str, people: int) -> None:
    if activity not in ACTIVITIES:
        raise ValueError(f"unknown activity: {activity}")
    if not 0 <= people <= 20:
        raise ValueError("people must be between 0 and 20")
    if activity == "empty" and people != 0:
        raise ValueError("activity=empty requires people=0")
    if activity != "empty" and people == 0:
        raise ValueError("non-empty activity requires people>=1")

"""Labels that separate cough from common overnight false positives."""

HEALTH_EVENT_LABELS = (
    "quiet_breathing",
    "cough",
    "sneeze",
    "throat_clear",
    "yawn",
    "speech",
    "bed_turn",
    "blanket_move",
    "other_motion",
)

TIMED_HEALTH_EVENTS = tuple(label for label in HEALTH_EVENT_LABELS if label != "quiet_breathing")


def validate_health_label(label: str) -> None:
    if label not in HEALTH_EVENT_LABELS:
        raise ValueError(f"unknown health event label: {label}")


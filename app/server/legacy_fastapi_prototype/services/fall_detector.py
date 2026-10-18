from collections import deque

_history: deque[tuple[float, float]] = deque(maxlen=10)


def update_and_detect(x: float, y: float) -> str:
    _history.append((x, y))

    if len(_history) < 3:
        return "normal"

    recent = list(_history)[-3:]
    diffs = [
        abs(recent[i][0] - recent[i - 1][0])
        + abs(recent[i][1] - recent[i - 1][1])
        for i in range(1, len(recent))
    ]
    avg_movement = sum(diffs) / len(diffs)

    if avg_movement < 0.01:
        return "danger"
    if avg_movement > 0.5:
        return "out"
    return "normal"


def pose_from_status(status: str) -> str:
    if status == "danger":
        return "lying"
    if status == "out":
        return "walking"
    return "standing"

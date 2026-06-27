from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any

STATE_FILE = Path(__file__).resolve().parent.parent / "dev_state.json"

DEFAULT_GUARDIANS = [
    {"id": 1, "name": "김영희 어르신", "phone": "010-0000-0000", "role": "보호 대상"},
    {"id": 2, "name": "김주환 보호자", "phone": "010-1234-5678", "role": "1순위 보호자"},
]

DEFAULT_SETTINGS = {
    "fallDetection": True,
    "stillnessDetection": True,
    "stillnessMinutes": 30,
    "intrusionDetection": True,
    "showPath": True,
    "showSensors": True,
    "miniatureSize": "medium",
}

DEFAULT_EMERGENCY_INFO = {
    "address": "경기도 수원시 ○○구 ○○로 123, 101동 1001호",
    "accessNote": "공동현관 호출 후 보호자에게 연락해 주세요.",
    "doorPassword": "",
    "medicalNote": "고혈압 약 복용 중. 낙상 의심 시 무리하게 일으키지 말아 주세요.",
    "hospital": "가까운 응급실: 아주대학교병원",
}

DEFAULT_LOCATION = {
    "x": 0.34,
    "y": 0.45,
    "status": "normal",
    "room": "거실",
    "pose": "standing",
    "confidence": 0.86,
    "source": "mock",
    "timestamp": "00:00:00",
}

DEFAULT_ALERTS = [
    {
        "id": 1,
        "type": "danger",
        "title": "낙상 의심 움직임 감지",
        "message": "거실 소파 근처에서 급격한 쓰러짐 패턴이 감지됐어요.",
        "room": "거실",
        "time": "오후 3:18",
        "urgent": True,
        "resolved": False,
    },
    {
        "id": 2,
        "type": "warning",
        "title": "현관 접근이 감지됐어요",
        "message": "현관 위험 구역에 접근했어요.",
        "room": "현관",
        "time": "오후 1:42",
        "urgent": False,
        "resolved": False,
    },
]


def _now_label() -> str:
    hour = datetime.now().hour
    minute = str(datetime.now().minute).zfill(2)
    prefix = "오전" if hour < 12 else "오후"
    display_hour = 12 if hour == 0 else hour - 12 if hour > 12 else hour
    return f"{prefix} {display_hour}:{minute}"


def _clamp_number(value: Any, fallback: float, minimum: float = 0, maximum: float = 1) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        number = float(fallback)
    return max(minimum, min(maximum, number))


def _room_from_position(x: float, y: float) -> str:
    if x > 0.62 and y < 0.42:
        return "주방"
    if x < 0.48 and y > 0.58:
        return "침실"
    if x > 0.68 and y > 0.55:
        return "현관"
    if 0.47 < x < 0.68 and y > 0.56:
        return "욕실"
    return "거실"


def _pose_from_status(status: str) -> str:
    if status == "danger":
        return "lying"
    if status == "out":
        return "walking"
    if status == "still":
        return "sitting"
    return "standing"


def _load() -> dict[str, Any]:
    if not STATE_FILE.exists():
        return {
            "guardians": DEFAULT_GUARDIANS.copy(),
            "settings": DEFAULT_SETTINGS.copy(),
            "emergencyInfo": DEFAULT_EMERGENCY_INFO.copy(),
            "location": DEFAULT_LOCATION.copy(),
            "alerts": DEFAULT_ALERTS.copy(),
        }

    try:
        saved = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        saved = {}

    return {
        "guardians": saved.get("guardians") or DEFAULT_GUARDIANS.copy(),
        "settings": {**DEFAULT_SETTINGS, **(saved.get("settings") or {})},
        "emergencyInfo": {
            **DEFAULT_EMERGENCY_INFO,
            **(saved.get("emergencyInfo") or {}),
        },
        "location": {**DEFAULT_LOCATION, **(saved.get("location") or {})},
        "alerts": saved.get("alerts") or DEFAULT_ALERTS.copy(),
    }


_state = _load()


def _save() -> None:
    STATE_FILE.write_text(
        json.dumps(_state | {"savedAt": datetime.now().isoformat()}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def get_state(tokens: int = 0) -> dict[str, Any]:
    return {
        "guardians": _state["guardians"],
        "settings": _state["settings"],
        "emergencyInfo": _state["emergencyInfo"],
        "location": _state["location"],
        "alerts": _state["alerts"],
        "tokens": tokens,
    }


def get_location() -> dict[str, Any]:
    return _state["location"]


def update_location(next_location: dict[str, Any]) -> dict[str, Any]:
    x = _clamp_number(next_location.get("x"), _state["location"]["x"])
    y = _clamp_number(next_location.get("y"), _state["location"]["y"])
    status = next_location.get("status")
    if status not in {"normal", "out", "danger", "still"}:
        status = _state["location"].get("status", "normal")

    _state["location"] = {
        **_state["location"],
        "x": round(x, 3),
        "y": round(y, 3),
        "status": status,
        "room": next_location.get("room") or _room_from_position(x, y),
        "pose": next_location.get("pose") or _pose_from_status(status),
        "confidence": round(
            _clamp_number(next_location.get("confidence"), 0.86),
            2,
        ),
        "source": next_location.get("source") or "sensor",
        "timestamp": datetime.now().strftime("%H:%M:%S"),
    }
    _save()
    return _state["location"]


def reset_demo() -> dict[str, Any]:
    _state["guardians"] = DEFAULT_GUARDIANS.copy()
    _state["settings"] = DEFAULT_SETTINGS.copy()
    _state["emergencyInfo"] = DEFAULT_EMERGENCY_INFO.copy()
    _state["location"] = {
        **DEFAULT_LOCATION,
        "timestamp": datetime.now().strftime("%H:%M:%S"),
        "source": "reset",
    }
    _state["alerts"] = []
    _save()
    return get_state()


def list_alerts() -> list[dict[str, Any]]:
    return _state["alerts"]


def add_alert(
    *,
    alert_type: str,
    title: str,
    message: str,
    room: str,
    urgent: bool = False,
) -> dict[str, Any]:
    alert = {
        "id": int(datetime.now().timestamp() * 1000),
        "type": alert_type,
        "title": title,
        "message": message,
        "room": room,
        "time": _now_label(),
        "urgent": urgent,
        "resolved": False,
    }
    _state["alerts"].insert(0, alert)
    _state["alerts"] = _state["alerts"][:80]
    _save()
    return alert


def resolve_alerts() -> list[dict[str, Any]]:
    _state["alerts"] = [
        {**alert, "urgent": False, "resolved": True}
        for alert in _state["alerts"]
    ]
    _save()
    return _state["alerts"]


def update_settings(next_settings: dict[str, Any]) -> dict[str, Any]:
    _state["settings"] = {**_state["settings"], **next_settings}
    _save()
    return _state["settings"]


def update_emergency_info(next_info: dict[str, Any]) -> dict[str, Any]:
    allowed_keys = {
        "address",
        "accessNote",
        "doorPassword",
        "medicalNote",
        "hospital",
    }
    sanitized = {key: value for key, value in next_info.items() if key in allowed_keys}
    _state["emergencyInfo"] = {
        **_state["emergencyInfo"],
        **sanitized,
    }
    _save()
    return _state["emergencyInfo"]


def add_guardian(name: str, phone: str, role: str) -> dict[str, Any]:
    guardian = {
        "id": int(datetime.now().timestamp() * 1000),
        "name": name,
        "phone": phone,
        "role": role,
    }
    _state["guardians"].append(guardian)
    _save()
    return guardian


def update_guardian(
    guardian_id: int,
    name: str | None = None,
    phone: str | None = None,
    role: str | None = None,
) -> dict[str, Any] | None:
    for index, guardian in enumerate(_state["guardians"]):
        if int(guardian.get("id", 0)) != guardian_id:
            continue

        next_guardian = {
            **guardian,
            "name": name or guardian.get("name", "보호자"),
            "phone": phone or guardian.get("phone", "010-0000-0000"),
            "role": role or guardian.get("role", "보호자"),
        }
        _state["guardians"][index] = next_guardian
        _save()
        return next_guardian

    return None


def delete_guardian(guardian_id: int) -> bool:
    before = len(_state["guardians"])
    _state["guardians"] = [
        guardian
        for guardian in _state["guardians"]
        if int(guardian.get("id", 0)) != guardian_id
    ]
    if len(_state["guardians"]) == before:
        return False
    _save()
    return True

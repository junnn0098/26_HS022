from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel

from routers import websocket as websocket_router
from services import fcm_service, store

router = APIRouter(tags=["state"])


class GuardianCreate(BaseModel):
    name: str = "새 보호자"
    phone: str = "010-0000-0000"
    role: str = "보호자"


class GuardianUpdate(BaseModel):
    id: int
    name: str | None = None
    phone: str | None = None
    role: str | None = None


class GuardianDelete(BaseModel):
    id: int


class ScenarioRequest(BaseModel):
    status: str = "danger"
    seconds: int = 12


class SensorLocationUpdate(BaseModel):
    x: float = 0.34
    y: float = 0.45
    status: str = "normal"
    room: str | None = None
    pose: str | None = None
    confidence: float = 0.86
    source: str = "sensor"


@router.get("/state")
def get_state():
    return store.get_state(tokens=fcm_service.token_count())


@router.get("/location/latest")
def get_latest_location():
    return {"location": store.get_location()}


@router.get("/alerts")
def get_alerts():
    return {"alerts": store.list_alerts()}


@router.post("/alerts/resolve")
def resolve_alerts():
    return {"status": "resolved", "alerts": store.resolve_alerts()}


@router.get("/settings")
def get_settings():
    return {"settings": store.get_state()["settings"]}


@router.post("/settings")
def update_settings(settings: dict[str, Any]):
    return {"status": "ok", "settings": store.update_settings(settings)}


@router.get("/emergency-info")
def get_emergency_info():
    return {"emergencyInfo": store.get_state()["emergencyInfo"]}


@router.post("/emergency-info")
def update_emergency_info(emergency_info: dict[str, Any]):
    return {
        "status": "ok",
        "emergencyInfo": store.update_emergency_info(emergency_info),
    }


@router.post("/sensor/update")
async def update_sensor_location(location: SensorLocationUpdate):
    next_location = store.update_location(location.model_dump(exclude_none=True))
    if next_location["status"] == "danger":
        store.add_alert(
            alert_type="danger",
            title="낙상 의심 움직임 감지",
            message=f"{next_location['room']}에서 급격한 쓰러짐 패턴이 감지됐어요.",
            room=next_location["room"],
            urgent=True,
        )
    await websocket_router.broadcast_location(next_location)
    return {"status": "ok", "location": next_location}


@router.post("/sensor/reset")
async def reset_sensor_location():
    location = store.update_location(
        {
            "x": 0.34,
            "y": 0.45,
            "status": "normal",
            "room": "거실",
            "pose": "standing",
            "source": "mock",
        }
    )
    await websocket_router.broadcast_location(location)
    return {
        "status": "ok",
        "location": location,
    }


@router.post("/demo/reset")
def reset_demo():
    return {"status": "ok", **store.reset_demo()}


@router.get("/guardians")
def get_guardians():
    return {"guardians": store.get_state()["guardians"]}


@router.post("/guardians")
def create_guardian(body: GuardianCreate):
    guardian = store.add_guardian(body.name, body.phone, body.role)
    return {
        "status": "ok",
        "guardian": guardian,
        "guardians": store.get_state()["guardians"],
    }


@router.post("/guardians/update")
def update_guardian(body: GuardianUpdate):
    guardian = store.update_guardian(body.id, body.name, body.phone, body.role)
    if guardian is None:
        return {
            "status": "not_found",
            "guardians": store.get_state()["guardians"],
        }
    return {
        "status": "ok",
        "guardian": guardian,
        "guardians": store.get_state()["guardians"],
    }


@router.post("/guardians/delete")
def delete_guardian(body: GuardianDelete):
    deleted = store.delete_guardian(body.id)
    return {
        "status": "ok" if deleted else "not_found",
        "guardians": store.get_state()["guardians"],
    }


@router.post("/scenario")
async def run_scenario(body: ScenarioRequest):
    status = body.status if body.status in {"normal", "out", "danger", "still"} else "danger"
    presets = {
        "normal": {
            "x": 0.34,
            "y": 0.45,
            "status": "normal",
            "room": "거실",
            "pose": "standing",
            "confidence": 0.88,
            "source": "scenario",
        },
        "out": {
            "x": 0.76,
            "y": 0.68,
            "status": "out",
            "room": "현관",
            "pose": "walking",
            "confidence": 0.88,
            "source": "scenario",
        },
        "danger": {
            "x": 0.36,
            "y": 0.45,
            "status": "danger",
            "room": "거실",
            "pose": "lying",
            "confidence": 0.91,
            "source": "scenario",
        },
        "still": {
            "x": 0.31,
            "y": 0.68,
            "status": "still",
            "room": "침실",
            "pose": "sitting",
            "confidence": 0.83,
            "source": "scenario",
        },
    }
    location = store.update_location(presets[status])

    if status == "danger":
        store.add_alert(
            alert_type="danger",
            title="시연용 낙상 의심 상황",
            message="시연 모드에서 위험 상황을 발생시켰어요.",
            room="거실",
            urgent=True,
        )
    elif status == "out":
        store.add_alert(
            alert_type="warning",
            title="현관 접근이 감지됐어요",
            message="현관 위험 구역에 접근했어요.",
            room="현관",
        )
    elif status == "still":
        store.add_alert(
            alert_type="warning",
            title="장시간 움직임이 적어요",
            message="침실에서 움직임이 오래 감지되지 않았어요.",
            room="침실",
        )

    await websocket_router.broadcast_location(location)

    return {
        "status": "ok",
        "scenario": {"status": status, "seconds": body.seconds},
        "location": location,
        "alerts": store.list_alerts(),
    }

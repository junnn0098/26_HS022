from typing import Literal

from pydantic import BaseModel


class LocationData(BaseModel):
    x: float
    y: float
    status: Literal["normal", "out", "danger", "still"]
    timestamp: str
    room: str = "거실"
    pose: Literal["standing", "walking", "lying", "sitting"] = "standing"
    confidence: float = 0.86


class CSIData(BaseModel):
    raw: list[float]
    device_id: str
    timestamp: str


class DeviceTokenRegister(BaseModel):
    token: str

import asyncio

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from models.schemas import LocationData
from services import fcm_service, store
from services.csi_parser import (
    generate_mock_csi,
    get_timestamp,
    parse_csi_to_location,
    room_from_position,
)
from services.fall_detector import pose_from_status, update_and_detect

router = APIRouter()

active_connections: list[WebSocket] = []


def _location_payload(location: dict) -> LocationData:
    x = float(location.get("x", 0.34))
    y = float(location.get("y", 0.45))
    status = location.get("status", "normal")
    return LocationData(
        x=x,
        y=y,
        status=status,
        room=location.get("room") or room_from_position(x, y),
        pose=location.get("pose") or pose_from_status(status),
        confidence=float(location.get("confidence", 0.86)),
        timestamp=location.get("timestamp") or get_timestamp(),
    )


async def broadcast_location(location: dict):
    if not active_connections:
        return

    message = _location_payload(location).model_dump_json()
    disconnected: list[WebSocket] = []
    for websocket in list(active_connections):
        try:
            await websocket.send_text(message)
        except Exception:
            disconnected.append(websocket)

    for websocket in disconnected:
        if websocket in active_connections:
            active_connections.remove(websocket)


@router.websocket("/ws/location")
async def websocket_location(websocket: WebSocket):
    await websocket.accept()
    active_connections.append(websocket)
    try:
        while True:
            latest = store.get_location()
            if latest.get("source") != "mock":
                x = float(latest.get("x", 0.34))
                y = float(latest.get("y", 0.45))
                status = latest.get("status", "normal")
                room = latest.get("room") or room_from_position(x, y)
                pose = latest.get("pose") or pose_from_status(status)
            else:
                csi = generate_mock_csi()
                x, y = parse_csi_to_location(csi)
                status = update_and_detect(x, y)
                room = room_from_position(x, y)
                pose = pose_from_status(status)

            if status == "danger":
                loop = asyncio.get_running_loop()
                loop.run_in_executor(None, fcm_service.send_fall_alert)

            data = LocationData(
                x=x,
                y=y,
                status=status,
                room=room,
                pose=pose,
                confidence=float(latest.get("confidence", 0.86)),
                timestamp=latest.get("timestamp") or get_timestamp(),
            )

            store.update_location(
                {
                    "x": data.x,
                    "y": data.y,
                    "status": data.status,
                    "room": data.room,
                    "pose": data.pose,
                    "confidence": data.confidence,
                    "source": latest.get("source", "mock"),
                }
            )

            await websocket.send_text(data.model_dump_json())
            await asyncio.sleep(1)

    except WebSocketDisconnect:
        if websocket in active_connections:
            active_connections.remove(websocket)

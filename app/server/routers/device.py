from fastapi import APIRouter

from models.schemas import DeviceTokenRegister
from services import fcm_service

router = APIRouter(prefix="/device", tags=["device"])


@router.post("/register")
def register_device(body: DeviceTokenRegister):
    fcm_service.register_token(body.token)
    return {"status": "ok"}

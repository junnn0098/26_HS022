from fastapi import APIRouter

from services import fcm_service
from services import store

router = APIRouter(prefix="/alarm", tags=["alarm"])


@router.post("/test")
def test_alarm():
    count = fcm_service.send_test_alert()
    store.add_alert(
        alert_type="system",
        title="테스트 알림을 보냈어요",
        message="보호자 알림 연결을 확인하기 위한 테스트입니다.",
        room="시스템",
    )
    return {"status": "sent", "recipients": count, "alerts": store.list_alerts()}

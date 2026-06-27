import os
import time

import firebase_admin
from firebase_admin import credentials, messaging

_tokens: list[str] = []
_last_alert_time: float = 0
_COOLDOWN_SECONDS = 60


def init_firebase():
    cred_path = os.getenv("FIREBASE_CREDENTIALS", "firebase_credentials.json")
    if os.path.exists(cred_path) and not firebase_admin._apps:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)


def register_token(token: str):
    if token not in _tokens:
        _tokens.append(token)


def token_count():
    return len(_tokens)


def send_fall_alert():
    global _last_alert_time
    if not _tokens or not firebase_admin._apps:
        return
    now = time.time()
    if now - _last_alert_time < _COOLDOWN_SECONDS:
        return
    _last_alert_time = now
    message = messaging.MulticastMessage(
        notification=messaging.Notification(
            title="⚠️ 낙상 위험 감지!",
            body="어르신의 낙상이 의심됩니다. 즉시 확인하세요.",
        ),
        data={"type": "fall_detected"},
        tokens=_tokens,
    )
    messaging.send_each_for_multicast(message)


def send_test_alert():
    if not _tokens or not firebase_admin._apps:
        return 0
    message = messaging.MulticastMessage(
        notification=messaging.Notification(
            title="🔔 알람 테스트",
            body="테스트 알람입니다. FCM 연결이 정상 동작합니다.",
        ),
        data={"type": "test"},
        tokens=_tokens,
    )
    messaging.send_each_for_multicast(message)
    return len(_tokens)

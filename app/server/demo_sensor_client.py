"""시연용 센서 클라이언트.

실제 Jetson/WiFi CSI 장비가 준비되기 전, 서버로 위치 데이터를 보내는 흐름을
확인하기 위한 표준 라이브러리 기반 예제입니다.
"""

from __future__ import annotations

import json
import time
import urllib.request


SERVER_URL = "http://127.0.0.1:8000"


SCENARIOS = [
    {
        "name": "정상 거실 이동",
        "payload": {
            "x": 0.34,
            "y": 0.45,
            "status": "normal",
            "pose": "standing",
            "confidence": 0.88,
            "source": "demo_sensor",
            "holdMs": 60000,
        },
    },
    {
        "name": "현관 접근",
        "payload": {
            "x": 0.76,
            "y": 0.68,
            "status": "out",
            "pose": "walking",
            "confidence": 0.88,
            "source": "demo_sensor",
            "holdMs": 60000,
        },
    },
    {
        "name": "낙상 의심",
        "payload": {
            "x": 0.36,
            "y": 0.45,
            "status": "danger",
            "pose": "lying",
            "confidence": 0.91,
            "source": "demo_sensor",
            "holdMs": 60000,
        },
    },
    {
        "name": "장시간 무반응",
        "payload": {
            "x": 0.31,
            "y": 0.68,
            "status": "still",
            "pose": "sitting",
            "confidence": 0.83,
            "source": "demo_sensor",
            "holdMs": 60000,
        },
    },
]


def post_json(path: str, payload: dict) -> dict:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{SERVER_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> None:
    print("Hanium demo sensor client")
    print(f"server: {SERVER_URL}")
    print("Ctrl+C로 종료할 수 있습니다.\n")

    while True:
        for scenario in SCENARIOS:
            print(f"send: {scenario['name']}")
            result = post_json("/sensor/update", scenario["payload"])
            print(json.dumps(result, ensure_ascii=False, indent=2))
            time.sleep(5)


if __name__ == "__main__":
    main()

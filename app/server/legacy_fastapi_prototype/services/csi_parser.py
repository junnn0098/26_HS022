import random
from datetime import datetime


def generate_mock_csi() -> list[float]:
    """Jetson 연결 전 Mock CSI 데이터 생성기."""
    return [random.gauss(0, 1) for _ in range(64)]


def parse_csi_to_location(csi_data: list[float]) -> tuple[float, float]:
    """실제 연결 시 이 함수에 CSI → 좌표 변환 알고리즘 삽입."""
    amplitude = [abs(v) for v in csi_data]
    x = (sum(amplitude[:32]) / 32) % 1.0
    y = (sum(amplitude[32:]) / 32) % 1.0
    return round(x, 3), round(y, 3)


def room_from_position(x: float, y: float) -> str:
    if x < 0.50 and y < 0.39:
        return "침실-2"
    if x >= 0.50 and y < 0.255:
        return "주방"
    if x < 0.50 and y < 0.565:
        return "거실"
    if 0.50 <= x < 0.72 and y < 0.565:
        return "욕실"
    if x < 0.50 and y >= 0.565:
        return "침실-1"
    return "현관"


def get_timestamp() -> str:
    return datetime.now().strftime("%H:%M:%S")

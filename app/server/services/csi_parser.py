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
    if x > 0.62 and y < 0.42:
        return "주방"
    if x < 0.48 and y > 0.58:
        return "침실"
    if x > 0.68 and y > 0.55:
        return "현관"
    if 0.47 < x < 0.68 and y > 0.56:
        return "욕실"
    return "거실"


def get_timestamp() -> str:
    return datetime.now().strftime("%H:%M:%S")

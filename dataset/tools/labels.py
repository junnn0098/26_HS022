"""수집 당시 기록한 동작 라벨과 분류 기준.

category
  fall       실제로 넘어지는 동작
  confusing  몸이 바닥 쪽으로 크게 내려가거나 균형을 잃어 낙상과 CSI 패턴이 비슷한 동작
  daily      일상 동작
"""


def anonymize(person: str | None, subjects: dict[str, str], where: str) -> str:
    """참여자 이름을 익명 ID로 바꾼다. 대응표에 없으면 이름을 출력하지 않고 멈춘다."""
    if not person:
        return "unrecorded"
    if person not in subjects:
        raise SystemExit(f"participant missing from --subject-map ({where})")
    return subjects[person]


LABELS = {
    "fall": {"ko": "낙상", "category": "fall"},
    "stumble_no_fall": {"ko": "비틀거리기(넘어지지 않음)", "category": "confusing"},
    "bend_pickup": {"ko": "허리 숙여 물건 줍기", "category": "confusing"},
    "walk_pickup": {"ko": "걸어다니며 물건 줍기", "category": "confusing"},
    "squat_stand": {"ko": "쪼그려 앉았다 일어나기", "category": "confusing"},
    "sit_lie": {"ko": "앉았다가 눕기(반복)", "category": "confusing"},
    "lie_stand": {"ko": "누웠다 일어나기", "category": "confusing"},
    "walking": {"ko": "걷기", "category": "daily"},
    "standing": {"ko": "가만히 서 있기", "category": "daily"},
    "sitting": {"ko": "가만히 앉아 있기", "category": "daily"},
    "sit_down": {"ko": "앉기", "category": "daily"},
    "sit_stand": {"ko": "앉았다 일어나기", "category": "daily"},
    "chair_workout": {"ko": "의자에서 움직이기", "category": "daily"},
    "arm_wave": {"ko": "팔 흔들기", "category": "daily"},
    "lying": {"ko": "누워 있기", "category": "daily"},
}

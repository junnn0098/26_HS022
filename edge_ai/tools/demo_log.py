#!/usr/bin/env python3
"""시연 영상용 CSI 실시간 로그 — 평상시 vs 낙상 '움직임 강도'를 터미널에 출력.

ESP(UDP 5005, ADR-018)에서 CSI를 받아 0.5초마다 한 줄씩:
  시각 · 노드별 pps · 평균 진폭 · 움직임 강도(막대) · 상태(평상/급변)
를 보여주고, logs/ 폴더에 같은 내용을 파일로 저장합니다.

학습된 모델이 없어도 동작합니다. 여기서 '상태'는 AI 낙상 판정이 아니라
움직임 강도 임계값 기반 표시입니다(시연용). 평상시엔 낮고, 낙상처럼 급격한
움직임이 있으면 수치가 확 튑니다.

사용법 (젯슨, 저장소 루트 hanium_jetson 에서):
    # 평상시 상황에서 녹화
    python3 demo_log.py --label normal

    # 낙상 재연하면서 녹화 (안전 매트 위에서)
    python3 demo_log.py --label fall

    # 임계값/노드 조정
    python3 demo_log.py --label fall --alert 40 --nodes 1,2,3,4
"""

from __future__ import annotations

import argparse
import socket
import time
from collections import defaultdict, deque
from datetime import datetime
from pathlib import Path

import numpy as np

# 저장소의 검증된 ADR-018 파서 재사용 (hanium_jetson 루트에서 실행)
from hanium_fall_v2.adr018 import parse_adr018

ANSI = {"reset": "\033[0m", "dim": "\033[90m", "green": "\033[92m",
        "yellow": "\033[93m", "red": "\033[91m", "cyan": "\033[96m", "bold": "\033[1m"}


def mean_amplitude(frame) -> float:
    """프레임의 LLTF 앞 64개 평균 진폭(0~약1.4로 정규화)."""
    iq = frame.iq[0].astype(np.float32)          # (subcarriers, 2)
    take = min(64, iq.shape[0])
    amp = np.hypot(iq[:take, 0], iq[:take, 1])
    return float(amp.mean()) / 128.0


def bar(value: float, width: int = 12) -> str:
    """0~100 값을 막대로."""
    filled = int(round(min(100.0, max(0.0, value)) / 100.0 * width))
    return "█" * filled + "░" * (width - filled)


def main() -> int:
    ap = argparse.ArgumentParser(description="시연용 CSI 움직임 로그")
    ap.add_argument("--label", default="demo", help="normal 또는 fall 등 (파일명에 들어감)")
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=5005)
    ap.add_argument("--nodes", default="1,2,3,4")
    ap.add_argument("--interval", type=float, default=0.5, help="출력 주기(초)")
    ap.add_argument("--alert", type=float, default=40.0, help="이 값 넘으면 '급변' 표시")
    ap.add_argument("--gain", type=float, default=600.0, help="움직임 민감도(평상시 보고 조정)")
    ap.add_argument("--duration", type=float, default=0.0, help="0이면 무한")
    ap.add_argument("--no-color", action="store_true")
    args = ap.parse_args()

    allowed = {int(x) for x in args.nodes.split(",") if x.strip()}
    C = {k: "" for k in ANSI} if args.no_color else ANSI

    logdir = Path("logs"); logdir.mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    logpath = logdir / f"demo_{args.label}_{stamp}.log"
    logfile = logpath.open("w", encoding="utf-8", buffering=1)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind((args.bind, args.port))
    sock.settimeout(0.05)

    # 노드별 최근 평균진폭 버퍼(움직임 계산용), pps 카운트
    recent = defaultdict(lambda: deque(maxlen=24))   # 약 0.7초치
    count = defaultdict(int)
    last_amp = {}

    header = (f"CSI DEMO LOG  label={args.label}  nodes={sorted(allowed)}  "
              f"port={args.port}  alert>{args.alert:.0f}")
    print(C["bold"] + header + C["reset"], flush=True)
    print(C["dim"] + f"저장: {logpath}" + C["reset"], flush=True)
    print(C["dim"] + "-" * 78 + C["reset"], flush=True)
    logfile.write(header + "\n")

    started = time.monotonic()
    next_print = started + args.interval
    deadline = started + args.duration if args.duration > 0 else float("inf")

    try:
        while time.monotonic() < deadline:
            try:
                data, _ = sock.recvfrom(65535)
            except socket.timeout:
                data = None
            if data is not None:
                try:
                    frame = parse_adr018(data)
                except ValueError:
                    frame = None
                if frame is not None and frame.node_id in allowed:
                    amp = mean_amplitude(frame)
                    recent[frame.node_id].append(amp)
                    last_amp[frame.node_id] = amp
                    count[frame.node_id] += 1

            now = time.monotonic()
            if now >= next_print:
                dt = now - (next_print - args.interval)
                # 움직임 강도 = 노드별 최근 진폭의 변동성 평균 × gain
                motions = []
                for n in allowed:
                    buf = recent[n]
                    if len(buf) >= 3:
                        motions.append(float(np.std(np.asarray(buf))))
                motion = (np.mean(motions) * args.gain) if motions else 0.0
                motion = min(100.0, motion)

                amps = [last_amp.get(n, 0.0) for n in allowed]
                mean_amp = float(np.mean(amps)) if amps else 0.0
                pps_txt = " ".join(f"n{n}:{count[n]/dt:4.0f}" for n in sorted(allowed))
                for n in allowed:
                    count[n] = 0

                if motion >= args.alert:
                    col, status = C["red"], "⚠ 급격한 움직임 (낙상 의심)"
                elif motion >= args.alert * 0.5:
                    col, status = C["yellow"], "· 움직임 감지"
                else:
                    col, status = C["green"], "평상"

                t = datetime.now().strftime("%H:%M:%S.") + f"{datetime.now().microsecond//100000}"
                line = (f"[{t}] {C['dim']}{pps_txt}{C['reset']}  "
                        f"amp {mean_amp:4.2f}  "
                        f"motion {motion:5.1f} {col}{bar(motion)}{C['reset']}  {col}{status}{C['reset']}")
                print(line, flush=True)
                # 파일엔 색코드 없이
                plain = (f"[{t}] {pps_txt}  amp {mean_amp:4.2f}  "
                         f"motion {motion:5.1f} {bar(motion)}  {status}")
                logfile.write(plain + "\n")
                next_print += args.interval
    except KeyboardInterrupt:
        pass
    finally:
        sock.close()
        logfile.close()
    print(C["dim"] + f"\n저장 완료: {logpath}" + C["reset"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

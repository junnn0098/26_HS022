#!/usr/bin/env python3
"""ESP32 CSI(UDP, ADR-018) → 대시보드(WebSocket) 실시간 브리지.

젯슨에서 실행합니다. ESP 4대가 UDP 5005로 보내는 ADR-018 CSI 프레임을 받아
노드별로 LLTF 64개 진폭(= sqrt(I^2+Q^2))을 계산하고, 웹 대시보드가 받을 수 있게
WebSocket(기본 8765)으로 JSON을 브로드캐스트합니다.

보내는 메시지 형식 (대시보드 csi_dashboard.html 이 그대로 받음):
    {"node": 1, "amplitudes": [64개 float], "rssi": -60, "pps": 41.2}

이 스크립트는 낙상 추론을 하지 않습니다. 파형 시각화용 "날 것" 진폭만 전달합니다.
저장소의 검증된 파서(hanium_fall_v2.adr018)를 그대로 재사용합니다.

노드가 신선도 시간(--stale-seconds, 기본 1.5초) 동안 새 프레임을 안 주면
그 노드는 전송에서 빠집니다. 그래서 ESP 한 대가 꺼지면 대시보드에서도
해당 노드가 "끊김"으로 보입니다.

사용법:
    pip install --break-system-packages websockets      # 최초 1회
    cd ~/hanium_jetson                                   # adr018.py import 되는 위치
    python3 csi_ws_bridge.py --udp-port 5005 --ws-port 8765 --nodes 1,2,3,4

    # 대시보드(csi_dashboard.html) 맨 위:
    #   const JETSON_WS_URL = "ws://192.168.0.15:8765";
"""

from __future__ import annotations

import argparse
import asyncio
import json
import socket
import threading
import time
from collections import defaultdict

import numpy as np

try:
    import websockets
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "websockets 패키지가 필요합니다. 먼저 실행하세요:\n"
        "    pip install --break-system-packages websockets"
    ) from exc

# 저장소의 검증된 ADR-018 파서를 그대로 사용 (firmware wire format과 1:1 일치)
from hanium_fall_v2.adr018 import LLTF_SUBCARRIERS, parse_adr018

CANONICAL = LLTF_SUBCARRIERS  # 64


def lltf_amplitude(frame) -> list[float]:
    """프레임에서 안테나 0, LLTF 앞 64개 subcarrier의 진폭을 반환.

    모델 추론처럼 20MHz/PPDU 를 엄격히 걸지 않고, 시각화를 위해 어떤 폭(64/128/192 등)이
    들어와도 앞쪽 64개를 쓰거나 모자라면 0으로 채운다.
    """
    iq = frame.iq  # (antennas, subcarriers, 2) int8
    sub = iq.shape[1]
    take = min(CANONICAL, sub)
    block = iq[0, :take, :].astype(np.float32)          # (take, 2)
    amp = np.hypot(block[:, 0], block[:, 1])            # (take,)
    if take < CANONICAL:
        amp = np.concatenate([amp, np.zeros(CANONICAL - take, dtype=np.float32)])
    # ESP32-S3 는 첫 2개 complex 가 무효일 수 있어 0 처리 (모델 파이프라인과 동일)
    amp[:2] = 0.0
    return [round(float(v), 3) for v in amp]


class LatestFrames:
    """UDP 스레드가 쓰고, WS 루프가 읽는 노드별 최신 진폭 저장소."""

    def __init__(self, stale_seconds: float) -> None:
        self._lock = threading.Lock()
        self._data: dict[int, dict] = {}
        self._last_seen: dict[int, float] = {}
        self._count: defaultdict[int, int] = defaultdict(int)
        self._win_start = time.monotonic()
        self._pps: dict[int, float] = {}
        self._stale = stale_seconds

    def update(self, node: int, amplitudes: list[float], rssi: int) -> None:
        with self._lock:
            self._data[node] = {"node": node, "amplitudes": amplitudes, "rssi": rssi}
            self._last_seen[node] = time.monotonic()
            self._count[node] += 1
            now = time.monotonic()
            if now - self._win_start >= 1.0:
                elapsed = now - self._win_start
                for n, c in self._count.items():
                    self._pps[n] = round(c / elapsed, 1)
                self._count.clear()
                self._win_start = now

    def fresh_snapshot(self) -> list[dict]:
        """신선도 시간 안에 새 프레임을 준 노드만 반환."""
        now = time.monotonic()
        with self._lock:
            out = []
            for node, msg in self._data.items():
                if now - self._last_seen.get(node, 0.0) > self._stale:
                    continue  # 끊긴 노드는 전송 안 함 → 대시보드에서 꺼짐
                m = dict(msg)
                m["pps"] = self._pps.get(node, 0.0)
                out.append(m)
            return out


def udp_receiver(stop: threading.Event, store: LatestFrames,
                 bind: str, port: int, allowed: set[int] | None) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((bind, port))
    sock.settimeout(0.5)
    print(f"[UDP] listening {bind}:{port}", flush=True)
    seen_nodes: set[int] = set()
    while not stop.is_set():
        try:
            data, _sender = sock.recvfrom(65535)
        except socket.timeout:
            continue
        except OSError:
            break
        try:
            frame = parse_adr018(data)
        except ValueError:
            continue
        if allowed and frame.node_id not in allowed:
            continue
        if frame.node_id not in seen_nodes:
            seen_nodes.add(frame.node_id)
            print(f"[UDP] node {frame.node_id} 수신 시작 (subcarriers={frame.subcarriers})", flush=True)
        store.update(frame.node_id, lltf_amplitude(frame), int(frame.rssi_dbm))
    sock.close()
    print("[UDP] stopped", flush=True)


async def ws_main(store: LatestFrames, ws_port: int, hz: float) -> None:
    clients: set = set()

    async def handler(conn):
        clients.add(conn)
        peer = getattr(conn, "remote_address", ("?", 0))
        print(f"[WS] client connected {peer} (총 {len(clients)})", flush=True)
        try:
            await conn.wait_closed()
        finally:
            clients.discard(conn)
            print(f"[WS] client disconnected (총 {len(clients)})", flush=True)

    async with websockets.serve(handler, "0.0.0.0", ws_port, ping_interval=20):
        print(f"[WS] serving ws://0.0.0.0:{ws_port}", flush=True)
        interval = 1.0 / hz
        while True:
            if clients:
                for msg in store.fresh_snapshot():
                    payload = json.dumps(msg, separators=(",", ":"))
                    dead = []
                    for c in clients:
                        try:
                            await c.send(payload)
                        except Exception:
                            dead.append(c)
                    for c in dead:
                        clients.discard(c)
            await asyncio.sleep(interval)


def main() -> int:
    ap = argparse.ArgumentParser(description="ESP CSI(UDP ADR-018) → WebSocket 브리지")
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--udp-port", type=int, default=5005)
    ap.add_argument("--ws-port", type=int, default=8765)
    ap.add_argument("--nodes", default="1,2,3,4",
                    help="허용 노드 ID (쉼표구분). 'all' 이면 전부 허용")
    ap.add_argument("--hz", type=float, default=30.0,
                    help="WebSocket 송신 빈도(노드별 최신값 기준)")
    ap.add_argument("--stale-seconds", type=float, default=1.5,
                    help="이 시간 동안 새 프레임이 없는 노드는 전송 중단")
    args = ap.parse_args()

    allowed = None
    if args.nodes.strip().lower() != "all":
        allowed = {int(x) for x in args.nodes.split(",") if x.strip()}

    store = LatestFrames(args.stale_seconds)
    stop = threading.Event()
    rx = threading.Thread(
        target=udp_receiver, args=(stop, store, args.bind, args.udp_port, allowed),
        daemon=True,
    )
    rx.start()

    try:
        asyncio.run(ws_main(store, args.ws_port, args.hz))
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        rx.join(timeout=2.0)
    print("RESULT=BRIDGE_STOPPED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

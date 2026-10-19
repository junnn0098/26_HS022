"""Real-time v1 inference: RuView UDP packets -> 500-frame buffer -> 1D-CNN -> alert.

This mirrors how the training windows were built (RuView align-ground-truth.js +
convert_for_ai_team_134ch_v3.py): every packet is one frame regardless of which
node sent it, only packets whose width equals the session's modal width are kept,
and amplitudes are read starting two bytes into the payload after the 8-byte
prefix. The first channels therefore contain header bytes; see data.py.

  python -m hanium_fall_v1.realtime_inference --weights hanium_fall_v1/weights/team_v1_0717.pth --channels all
"""

from __future__ import annotations

import argparse
import json
import socket
import time
from collections import deque
from pathlib import Path

import numpy as np

from .data import preprocess
from .model import FALL_INDEX, IN_CHANNELS, CSI1DCNN

PREFIX_BYTES = 8  # magic(4) node_id(1) antennas(1) subcarriers(2) of the ADR-018 header
WINDOW = 500
STRIDE = 50  # run the model every 50 frames (about 0.5 s)


def packet_width(data: bytes) -> int:
    """Width as the RuView recorder stored it: bytes after the prefix // 2."""
    return (len(data) - PREFIX_BYTES) // 2


def packet_to_frame(data: bytes) -> np.ndarray:
    """One UDP datagram -> one 134-value frame, identical to the training extractor."""
    payload = np.frombuffer(data[PREFIX_BYTES:], dtype=np.int8).astype(np.float32)
    frame = np.zeros(IN_CHANNELS, dtype=np.float32)
    pairs = min(IN_CHANNELS, (len(payload) - 2) // 2)
    i, q = payload[2:2 + 2 * pairs:2], payload[3:3 + 2 * pairs:2]
    frame[:pairs] = np.sqrt(i * i + q * q)
    return frame


class AlertGate:
    """Two-threshold gate used by the team: high -> alert now, middle -> confirm twice."""

    def __init__(self, high: float = 0.9, low: float = 0.5, confirmations: int = 2):
        self.high, self.low, self.confirmations = high, low, confirmations
        self.hits = 0

    def update(self, probability: float) -> str | None:
        if probability >= self.high:
            self.hits = 0
            return "immediate"
        if probability >= self.low:
            self.hits += 1
            if self.hits >= self.confirmations:
                self.hits = 0
                return "confirmed"
            return None
        self.hits = 0
        return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--weights", type=Path, required=True)
    parser.add_argument("--channels", choices=("all", "csi", "lltf"),
                        help="channel set used in training (default: read from the weights' .json card, else all)")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5005)
    parser.add_argument("--width", type=int, default=0,
                        help="packet width to keep (0 = learn the modal width from the first 400 packets)")
    args = parser.parse_args()

    import torch

    card = args.weights.with_suffix(".json")
    channels = args.channels or (json.loads(card.read_text(encoding="utf-8"))["channels"] if card.exists() else "all")
    model = CSI1DCNN()
    model.load_state_dict(torch.load(args.weights, map_location="cpu", weights_only=True))
    model.eval()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.host, args.port))
    print(f"listening on {args.host}:{args.port} | weights={args.weights.name} channels={channels}")

    width, seen = args.width, []
    buffer: deque[np.ndarray] = deque(maxlen=WINDOW)
    gate, count = AlertGate(), 0
    while True:
        data, _ = sock.recvfrom(65535)
        if len(data) <= PREFIX_BYTES + 2:
            continue
        if not width:
            seen.append(packet_width(data))
            if len(seen) >= 400:
                width = max(set(seen), key=seen.count)
                print(f"modal packet width: {width}")
            continue
        if packet_width(data) != width:
            continue
        buffer.append(packet_to_frame(data))
        count += 1
        if len(buffer) < WINDOW or count % STRIDE:
            continue
        x = torch.from_numpy(preprocess(np.stack(buffer), channels)[None])
        with torch.no_grad():
            probability = float(torch.softmax(model(x), dim=1)[0, FALL_INDEX])
        level = gate.update(probability)
        if level:
            print(f"[{time.strftime('%H:%M:%S')}] FALL ({level}) p={probability:.3f}", flush=True)
        else:
            print(f"  p_fall={probability:.3f}", end="\r", flush=True)


if __name__ == "__main__":
    main()

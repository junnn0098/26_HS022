"""Replay a recorded RuView session as live UDP packets (sensor-free demo of the realtime path).

The recorder stored every ADR-018 packet without its first 8 bytes; this script
puts them back and sends the packets with their original timing (or faster).

  python -m hanium_fall_v1.realtime_inference --weights hanium_fall_v1/weights/team_v1_0717.pth --port 5005
  python -m hanium_fall_v1.replay_recording ../dataset/sample/raw/csi-1783443615.fall-12s.csi.jsonl.gz
  python -m hanium_fall_v1.replay_recording ../dataset/raw/recordings/csi-1783443615.csi.jsonl --speed 4

Gzip-compressed recordings (.jsonl.gz) are read directly.
"""

from __future__ import annotations

import argparse
import gzip
import json
import socket
import struct
import time
from pathlib import Path

PREFIX = struct.Struct("<IBBH")
MAGIC = 0xC5110001


def packet(record: dict) -> bytes:
    return PREFIX.pack(MAGIC, int(record["node_id"]), 1, int(record["subcarriers"]) - 6) + bytes.fromhex(record["iq_hex"])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("recording", type=Path, help="csi-<epoch>.csi.jsonl from dataset/raw/recordings")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5005)
    parser.add_argument("--speed", type=float, default=1.0, help="playback speed (1 = real time)")
    parser.add_argument("--seconds", type=float, default=0.0, help="stop after this many recorded seconds (0 = all)")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    started = time.monotonic()
    first_ns = None
    sent = 0
    opener = gzip.open if args.recording.suffix == ".gz" else open
    offset = 0.0
    with opener(args.recording, "rt", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("type") != "raw_csi":
                continue
            first_ns = first_ns if first_ns is not None else int(record["ts_ns"])
            offset = (int(record["ts_ns"]) - first_ns) / 1e9
            if args.seconds and offset > args.seconds:
                break
            delay = offset / args.speed - (time.monotonic() - started)
            if delay > 0:
                time.sleep(delay)
            sock.sendto(packet(record), (args.host, args.port))
            sent += 1
    print(f"sent {sent} packets ({offset:.1f} s of recording) to {args.host}:{args.port}")


if __name__ == "__main__":
    main()

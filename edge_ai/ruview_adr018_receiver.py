#!/usr/bin/env python3
"""RuView ADR-018 UDP receiver and capture validator.

Built for the current ESP32-S3 firmware wire format:
  0..3   magic 0xC5110001 (little-endian u32)
  4      node id (u8)
  5      antenna count (u8)
  6..7   subcarrier count (little-endian u16)
  8..11  center frequency MHz (little-endian u32)
  12..15 sequence number (little-endian u32)
  16     RSSI dBm (i8)
  17     noise floor dBm (i8)
  18     PPDU metadata (u8)
  19     flags (u8)
  20..   signed int8 I/Q pairs

This program intentionally does not contain a fall model. Its job is to prove
the firmware-to-Jetson data contract and optionally save amplitude frames for
training a model that matches the current firmware.
"""

from __future__ import annotations

import argparse
import json
import signal
import socket
import struct
import sys
import time
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, TextIO

import numpy as np


MAGIC = 0xC5110001
HEADER = struct.Struct("<IBBHIIbbBB")
HEADER_SIZE = HEADER.size


@dataclass(frozen=True)
class CsiFrame:
    node_id: int
    antennas: int
    subcarriers: int
    frequency_mhz: int
    sequence: int
    rssi_dbm: int
    noise_floor_dbm: int
    ppdu: int
    flags: int
    amplitude: np.ndarray
    packet_size: int
    trailing_bytes: int


def parse_adr018(data: bytes) -> CsiFrame:
    if len(data) < HEADER_SIZE:
        raise ValueError(f"short packet: {len(data)} < {HEADER_SIZE}")

    (
        magic,
        node_id,
        antennas,
        subcarriers,
        frequency_mhz,
        sequence,
        rssi_dbm,
        noise_floor_dbm,
        ppdu,
        flags,
    ) = HEADER.unpack_from(data)

    if magic != MAGIC:
        raise ValueError(f"different magic: 0x{magic:08X}")
    if not 1 <= antennas <= 4:
        raise ValueError(f"invalid antenna count: {antennas}")
    if not 1 <= subcarriers <= 2048:
        raise ValueError(f"invalid subcarrier count: {subcarriers}")

    sample_count = antennas * subcarriers
    iq_byte_count = sample_count * 2
    expected_size = HEADER_SIZE + iq_byte_count
    if len(data) < expected_size:
        raise ValueError(
            f"truncated I/Q: got {len(data)} bytes, expected at least {expected_size} "
            f"for {antennas}x{subcarriers}"
        )

    iq = np.frombuffer(
        data,
        dtype=np.int8,
        count=iq_byte_count,
        offset=HEADER_SIZE,
    ).astype(np.float32, copy=False)
    iq = iq.reshape(sample_count, 2)
    amplitude = np.hypot(iq[:, 0], iq[:, 1])
    if antennas > 1:
        amplitude = amplitude.reshape(antennas, subcarriers)

    return CsiFrame(
        node_id=node_id,
        antennas=antennas,
        subcarriers=subcarriers,
        frequency_mhz=frequency_mhz,
        sequence=sequence,
        rssi_dbm=rssi_dbm,
        noise_floor_dbm=noise_floor_dbm,
        ppdu=ppdu,
        flags=flags,
        amplitude=amplitude,
        packet_size=len(data),
        trailing_bytes=len(data) - expected_size,
    )


class ReceiverStats:
    def __init__(self) -> None:
        self.started = time.monotonic()
        self.interval_started = self.started
        self.total_datagrams = 0
        self.valid_frames = 0
        self.interval_valid = 0
        self.invalid_packets = 0
        self.invalid_reasons: Counter[str] = Counter()
        self.nodes: Counter[int] = Counter()
        self.subcarriers: Counter[int] = Counter()
        self.packet_sizes: Counter[int] = Counter()
        self.trailing_sizes: Counter[int] = Counter()
        self.last_sequence: dict[int, int] = {}
        self.sequence_gaps: defaultdict[int, int] = defaultdict(int)
        self.duplicates_or_reordered: defaultdict[int, int] = defaultdict(int)

    def add_frame(self, frame: CsiFrame) -> None:
        self.valid_frames += 1
        self.interval_valid += 1
        self.nodes[frame.node_id] += 1
        self.subcarriers[frame.subcarriers] += 1
        self.packet_sizes[frame.packet_size] += 1
        if frame.trailing_bytes:
            self.trailing_sizes[frame.trailing_bytes] += 1

        previous = self.last_sequence.get(frame.node_id)
        if previous is not None:
            delta = (frame.sequence - previous) & 0xFFFFFFFF
            if delta == 0 or delta >= 0x80000000:
                self.duplicates_or_reordered[frame.node_id] += 1
            elif delta > 1:
                self.sequence_gaps[frame.node_id] += delta - 1
        self.last_sequence[frame.node_id] = frame.sequence

    def interval_report(self) -> tuple[float, float]:
        now = time.monotonic()
        elapsed = max(now - self.interval_started, 1e-9)
        interval_pps = self.interval_valid / elapsed
        average_pps = self.valid_frames / max(now - self.started, 1e-9)
        self.interval_started = now
        self.interval_valid = 0
        return interval_pps, average_pps


def frame_json(frame: CsiFrame, sender: tuple[str, int]) -> dict[str, object]:
    return {
        "received_unix_ns": time.time_ns(),
        "received_monotonic_ns": time.monotonic_ns(),
        "sender_ip": sender[0],
        "sender_port": sender[1],
        "node_id": frame.node_id,
        "antennas": frame.antennas,
        "subcarriers": frame.subcarriers,
        "frequency_mhz": frame.frequency_mhz,
        "sequence": frame.sequence,
        "rssi_dbm": frame.rssi_dbm,
        "noise_floor_dbm": frame.noise_floor_dbm,
        "ppdu": frame.ppdu,
        "flags": frame.flags,
        "packet_size": frame.packet_size,
        "trailing_bytes": frame.trailing_bytes,
        "amplitude": frame.amplitude.reshape(-1).round(6).tolist(),
    }


def print_summary(stats: ReceiverStats) -> None:
    elapsed = max(time.monotonic() - stats.started, 1e-9)
    print("\nFINAL_SUMMARY", flush=True)
    print(f"  elapsed_seconds={elapsed:.3f}")
    print(f"  total_datagrams={stats.total_datagrams}")
    print(f"  valid_adr018_frames={stats.valid_frames}")
    print(f"  average_valid_pps={stats.valid_frames / elapsed:.3f}")
    print(f"  invalid_packets={stats.invalid_packets}")
    print(f"  nodes={dict(sorted(stats.nodes.items()))}")
    print(f"  subcarrier_counts={dict(sorted(stats.subcarriers.items()))}")
    print(f"  packet_sizes={dict(sorted(stats.packet_sizes.items()))}")
    print(f"  trailing_sizes={dict(sorted(stats.trailing_sizes.items()))}")
    print(f"  sequence_gaps={dict(sorted(stats.sequence_gaps.items()))}")
    print(
        "  duplicates_or_reordered="
        f"{dict(sorted(stats.duplicates_or_reordered.items()))}"
    )
    print(f"  invalid_reasons={dict(stats.invalid_reasons.most_common(8))}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate and optionally record current RuView ADR-018 CSI frames."
    )
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5005)
    parser.add_argument("--duration", type=float, default=30.0)
    parser.add_argument("--print-every", type=float, default=1.0)
    parser.add_argument("--save-jsonl", type=Path)
    parser.add_argument("--expect-node", type=int)
    parser.add_argument("--expect-subcarriers", type=int)
    args = parser.parse_args()

    if args.duration <= 0:
        parser.error("--duration must be greater than zero")
    if args.print_every <= 0:
        parser.error("--print-every must be greater than zero")

    output: TextIO | None = None
    if args.save_jsonl:
        args.save_jsonl.parent.mkdir(parents=True, exist_ok=True)
        output = args.save_jsonl.open("x", encoding="utf-8", buffering=1)

    stats = ReceiverStats()
    stop_requested = False

    def request_stop(_signum: int, _frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind((args.bind, args.port))
    sock.settimeout(0.25)
    actual_rcvbuf = sock.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)

    print(
        f"ADR018_RECEIVER_READY bind={args.bind}:{args.port} "
        f"duration={args.duration:.1f}s rcvbuf={actual_rcvbuf}",
        flush=True,
    )
    if output:
        print(f"CAPTURE_PATH={args.save_jsonl.resolve()}", flush=True)

    deadline = stats.started + args.duration
    next_report = stats.started + args.print_every
    first_frame_printed = False

    try:
        while not stop_requested and time.monotonic() < deadline:
            try:
                data, sender = sock.recvfrom(65535)
            except socket.timeout:
                data = b""
                sender = ("", 0)
            else:
                stats.total_datagrams += 1
                try:
                    frame = parse_adr018(data)
                except ValueError as exc:
                    stats.invalid_packets += 1
                    stats.invalid_reasons[str(exc).split(":", 1)[0]] += 1
                else:
                    stats.add_frame(frame)
                    if not first_frame_printed:
                        print(
                            "FIRST_VALID_FRAME "
                            f"sender={sender[0]}:{sender[1]} node={frame.node_id} "
                            f"antennas={frame.antennas} subcarriers={frame.subcarriers} "
                            f"frequency_mhz={frame.frequency_mhz} sequence={frame.sequence} "
                            f"rssi_dbm={frame.rssi_dbm} packet_size={frame.packet_size} "
                            f"trailing={frame.trailing_bytes}",
                            flush=True,
                        )
                        first_frame_printed = True
                    if output:
                        output.write(json.dumps(frame_json(frame, sender), separators=(",", ":")) + "\n")

            now = time.monotonic()
            if now >= next_report:
                interval_pps, average_pps = stats.interval_report()
                print(
                    f"LIVE valid={stats.valid_frames} interval_pps={interval_pps:.2f} "
                    f"average_pps={average_pps:.2f} invalid={stats.invalid_packets} "
                    f"nodes={dict(stats.nodes)} nsub={dict(stats.subcarriers)} "
                    f"gaps={dict(stats.sequence_gaps)}",
                    flush=True,
                )
                next_report = now + args.print_every
    finally:
        sock.close()
        if output:
            output.close()

    print_summary(stats)

    if stats.valid_frames == 0:
        print("RESULT=FAIL_NO_ADR018_FRAMES", file=sys.stderr)
        return 2
    if args.expect_node is not None and stats.nodes[args.expect_node] == 0:
        print(f"RESULT=FAIL_EXPECTED_NODE_{args.expect_node}_NOT_SEEN", file=sys.stderr)
        return 3
    if (
        args.expect_subcarriers is not None
        and stats.subcarriers[args.expect_subcarriers] == 0
    ):
        print(
            f"RESULT=FAIL_EXPECTED_SUBCARRIERS_{args.expect_subcarriers}_NOT_SEEN",
            file=sys.stderr,
        )
        return 4

    print("RESULT=PASS_ADR018_STREAM_VALIDATED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

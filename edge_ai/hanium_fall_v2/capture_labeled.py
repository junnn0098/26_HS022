"""Capture labeled ADR-018 sessions using only the 64-value LLTF block."""

from __future__ import annotations

import argparse
import json
import math
import os
import signal
import socket
import sys
import time
import uuid
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from .adr018 import (
    CANONICAL_SUBCARRIERS,
    LLTF_INVALID_PREFIX_COMPLEX,
    LLTF_SUBCARRIERS,
    LTF_SELECTION_POLICY,
    NORMALIZATION_POLICY,
    extract_lltf_iq,
    parse_adr018,
    sequence_gap,
)
from .labels import ACTIVITIES, EVENT_ACTIVITIES, people_bucket, validate_label


SCHEMA_VERSION = "hanium.ruview.csi.session.v1"


def parse_nodes(value: str) -> tuple[int, ...]:
    try:
        nodes = tuple(sorted({int(part.strip()) for part in value.split(",")}))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("nodes must be comma-separated integers") from exc
    if not nodes or any(node < 1 or node > 255 for node in nodes):
        raise argparse.ArgumentTypeError("nodes must be between 1 and 255")
    return nodes


def safe_name(value: str) -> str:
    cleaned = "".join(ch if ch.isalnum() or ch in "-_" else "-" for ch in value)
    return cleaned.strip("-") or "session"


def parse_participants(value: str) -> tuple[str, ...]:
    participants = tuple(sorted({item.strip() for item in value.split(",") if item.strip()}))
    if any(len(item) > 64 for item in participants):
        raise argparse.ArgumentTypeError("participant ids must be at most 64 characters")
    return participants


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Record a labeled, lossless ADR-018 CSI session."
    )
    parser.add_argument("--activity", required=True, choices=ACTIVITIES)
    parser.add_argument("--people", required=True, type=int)
    parser.add_argument("--subject", required=True, help="Anonymous subject/group id")
    parser.add_argument(
        "--participants",
        type=parse_participants,
        default=(),
        help="Comma-separated anonymous participant ids; required when people > 1",
    )
    parser.add_argument("--room", default="room_unknown", help="Stable anonymous room id")
    parser.add_argument("--session", default="", help="Optional repeat/session id")
    parser.add_argument("--notes", default="")
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5005)
    parser.add_argument("--duration", type=float, default=60.0)
    parser.add_argument("--countdown", type=int, default=5)
    parser.add_argument(
        "--event-at",
        type=float,
        help="Seconds after capture start to print EVENT_GO; required for transition/fall labels",
    )
    parser.add_argument("--print-every", type=float, default=5.0)
    parser.add_argument("--nodes", type=parse_nodes, default=(1,))
    parser.add_argument(
        "--subcarriers",
        type=int,
        default=CANONICAL_SUBCARRIERS,
        help="Canonical model width; fixed at 64 for 20 MHz CSI",
    )
    parser.add_argument("--min-pps-per-node", type=float, default=20.0)
    parser.add_argument("--output-dir", type=Path, default=Path("captures"))
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        validate_label(args.activity, args.people)
    except ValueError as exc:
        parser.error(str(exc))
    if args.duration < 10:
        parser.error("--duration must be at least 10 seconds")
    if args.countdown < 0:
        parser.error("--countdown must be non-negative")
    if args.print_every <= 0 or args.min_pps_per_node <= 0:
        parser.error("print interval and minimum pps must be positive")
    if args.subcarriers != CANONICAL_SUBCARRIERS:
        parser.error(
            f"--subcarriers must be {CANONICAL_SUBCARRIERS}; "
            "raw 64/128/192 frames are reduced to LLTF automatically"
        )
    if args.people == 0 and args.participants:
        parser.error("activity=empty cannot have --participants")
    if args.people == 1 and not args.participants:
        args.participants = (args.subject,)
    if args.people > 1 and not args.participants:
        parser.error("people > 1 requires --participants person01,person02,...")
    if args.people > 0 and len(args.participants) != args.people:
        parser.error("--participants count must equal --people")
    if args.activity in EVENT_ACTIVITIES and args.event_at is None:
        parser.error(f"activity={args.activity} requires --event-at")
    if args.activity not in EVENT_ACTIVITIES and args.event_at is not None:
        parser.error("--event-at is only valid for sit_down/lie_down/stand_up/fall")
    if args.event_at is not None and not 1.0 <= args.event_at <= args.duration - 2.0:
        parser.error("--event-at must leave at least 1s before and 2s after the event")

    stop_requested = False

    def request_stop(_signum: int, _frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    try:
        sock.bind((args.bind, args.port))
    except OSError as exc:
        print(f"RESULT=FAIL_BIND error={exc}", file=sys.stderr)
        return 10
    sock.settimeout(0.25)

    print(
        f"CAPTURE_ARMED bind={args.bind}:{args.port} activity={args.activity} "
        f"people={args.people} nodes={args.nodes} subcarriers={args.subcarriers}",
        flush=True,
    )
    for remaining in range(args.countdown, 0, -1):
        print(f"START_IN={remaining}", flush=True)
        time.sleep(1)

    # The socket is already bound during the countdown so that a port conflict is
    # detected before the participant moves. Discard the queued countdown frames;
    # otherwise they would be timestamped as if they arrived at capture start and
    # would inflate the first interval's packet rate.
    countdown_backlog = 0
    sock.setblocking(False)
    while True:
        try:
            sock.recvfrom(65535)
        except BlockingIOError:
            break
        else:
            countdown_backlog += 1
    sock.settimeout(0.25)
    print(f"COUNTDOWN_BACKLOG_DROPPED={countdown_backlog}", flush=True)

    started_monotonic = time.monotonic()
    started_monotonic_ns = time.monotonic_ns()
    started_unix_ns = time.time_ns()
    deadline = started_monotonic + args.duration
    next_report = started_monotonic + args.print_every

    iq_frames: list[np.ndarray] = []
    received_unix_ns: list[int] = []
    received_monotonic_ns: list[int] = []
    sender_ip: list[str] = []
    sender_port: list[int] = []
    node_id: list[int] = []
    sequence: list[int] = []
    frequency_mhz: list[int] = []
    rssi_dbm: list[int] = []
    noise_floor_dbm: list[int] = []
    ppdu: list[int] = []
    flags: list[int] = []
    packet_size: list[int] = []
    trailing_bytes: list[int] = []
    source_subcarriers: list[int] = []

    datagrams = 0
    valid_by_node: Counter[int] = Counter()
    raw_subcarrier_counts: Counter[int] = Counter()
    raw_subcarrier_counts_by_node: defaultdict[int, Counter[int]] = defaultdict(Counter)
    ppdu_counts: Counter[int] = Counter()
    flags_counts: Counter[int] = Counter()
    invalid_reasons: Counter[str] = Counter()
    filtered_reasons: Counter[str] = Counter()
    gaps: defaultdict[int, int] = defaultdict(int)
    reordered: defaultdict[int, int] = defaultdict(int)
    last_sequence: dict[int, int] = {}

    print("CAPTURE_STARTED", flush=True)
    event_announced = False
    event_offset_actual: float | None = None
    last_event_countdown: int | None = None
    if args.activity == "fall":
        print("SAFETY=USE_MAT_AND_SPOTTER_NEVER_PERFORM_AN_UNSAFE_FALL", flush=True)
    try:
        while not stop_requested and time.monotonic() < deadline:
            elapsed_before_receive = time.monotonic() - started_monotonic
            if args.event_at is not None and not event_announced:
                remaining = int(math.ceil(args.event_at - elapsed_before_receive))
                if remaining > 0 and remaining != last_event_countdown:
                    print(f"EVENT_IN={remaining}", flush=True)
                    last_event_countdown = remaining
                elif elapsed_before_receive >= args.event_at:
                    event_announced = True
                    event_offset_actual = elapsed_before_receive
                    print(f"EVENT_GO={args.activity}", flush=True)
            try:
                data, sender = sock.recvfrom(65535)
            except socket.timeout:
                pass
            else:
                datagrams += 1
                now_unix_ns = time.time_ns()
                now_monotonic_ns = time.monotonic_ns()
                try:
                    frame = parse_adr018(data)
                except ValueError as exc:
                    invalid_reasons[str(exc).split(":", 1)[0]] += 1
                    continue
                if frame.node_id not in args.nodes:
                    filtered_reasons["unexpected node"] += 1
                    continue
                try:
                    canonical_iq = extract_lltf_iq(frame, args.subcarriers)
                except ValueError as exc:
                    filtered_reasons[str(exc).split(":", 1)[0]] += 1
                    continue

                previous = last_sequence.get(frame.node_id)
                if previous is not None:
                    gap = sequence_gap(previous, frame.sequence)
                    if gap < 0:
                        reordered[frame.node_id] += 1
                    else:
                        gaps[frame.node_id] += gap
                last_sequence[frame.node_id] = frame.sequence

                iq_frames.append(canonical_iq)
                received_unix_ns.append(now_unix_ns)
                received_monotonic_ns.append(now_monotonic_ns)
                sender_ip.append(sender[0])
                sender_port.append(sender[1])
                node_id.append(frame.node_id)
                sequence.append(frame.sequence)
                frequency_mhz.append(frame.frequency_mhz)
                rssi_dbm.append(frame.rssi_dbm)
                noise_floor_dbm.append(frame.noise_floor_dbm)
                ppdu.append(frame.ppdu)
                flags.append(frame.flags)
                packet_size.append(frame.packet_size)
                trailing_bytes.append(frame.trailing_bytes)
                source_subcarriers.append(frame.subcarriers)
                valid_by_node[frame.node_id] += 1
                raw_subcarrier_counts[frame.subcarriers] += 1
                raw_subcarrier_counts_by_node[frame.node_id][frame.subcarriers] += 1
                ppdu_counts[frame.ppdu] += 1
                flags_counts[frame.flags] += 1

            now = time.monotonic()
            if now >= next_report:
                elapsed = max(now - started_monotonic, 1e-9)
                rates = {
                    node: round(valid_by_node[node] / elapsed, 2) for node in args.nodes
                }
                print(
                    f"LIVE elapsed={elapsed:.1f}s valid={len(iq_frames)} "
                    f"pps_by_node={rates} invalid={sum(invalid_reasons.values())}",
                    flush=True,
                )
                next_report = now + args.print_every
    finally:
        sock.close()

    ended_monotonic = time.monotonic()
    elapsed = max(ended_monotonic - started_monotonic, 1e-9)
    if not iq_frames:
        print("RESULT=FAIL_NO_VALID_FRAMES", file=sys.stderr)
        return 2

    shapes = {tuple(frame.shape) for frame in iq_frames}
    if len(shapes) != 1:
        print(f"RESULT=FAIL_MIXED_IQ_SHAPES shapes={sorted(shapes)}", file=sys.stderr)
        return 3

    wall_clock_ok = time.time() >= 1_704_067_200  # 2024-01-01 UTC
    if wall_clock_ok:
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    else:
        timestamp = f"UNSYNCED_{time.monotonic_ns()}_{uuid.uuid4().hex[:8]}"
    session = safe_name(args.session or timestamp)
    stem = (
        f"{timestamp}_{safe_name(args.activity)}_p{people_bucket(args.people)}_"
        f"{safe_name(args.subject)}_{session}"
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    capture_path = args.output_dir / f"{stem}.npz"
    summary_path = args.output_dir / f"{stem}.summary.json"

    rates = {str(node): valid_by_node[node] / elapsed for node in args.nodes}
    metadata = {
        "schema": SCHEMA_VERSION,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "wall_clock_synchronized": wall_clock_ok,
        "activity": args.activity,
        "people_actual": args.people,
        "people_bucket": people_bucket(args.people),
        "subject": args.subject,
        "participants": list(args.participants),
        "room": args.room,
        "session": session,
        "notes": args.notes,
        "expected_nodes": list(args.nodes),
        "expected_subcarriers": args.subcarriers,
        "canonical_subcarriers": args.subcarriers,
        "normalization_policy": NORMALIZATION_POLICY,
        "selected_ltf": "LLTF",
        "ltf_selection_policy": LTF_SELECTION_POLICY,
        "lltf_subcarriers": LLTF_SUBCARRIERS,
        "lltf_first_word_masked_complex_values": LLTF_INVALID_PREFIX_COMPLEX,
        "accepted_raw_subcarriers": [64, 128, 192],
        "raw_subcarrier_counts": dict(raw_subcarrier_counts),
        "raw_subcarrier_counts_by_node": {
            str(node): dict(counts)
            for node, counts in sorted(raw_subcarrier_counts_by_node.items())
        },
        "accepted_ppdu_counts": dict(ppdu_counts),
        "accepted_flags_counts": dict(flags_counts),
        "target_resample_hz": 32,
        "window_seconds": 5,
        "window_frames": 160,
        "capture_started_unix_ns": started_unix_ns,
        "capture_started_monotonic_ns": started_monotonic_ns,
        "capture_elapsed_seconds": elapsed,
        "countdown_backlog_dropped": countdown_backlog,
        "datagrams": datagrams,
        "valid_frames": len(iq_frames),
        "valid_by_node": dict(valid_by_node),
        "pps_by_node": rates,
        "invalid_reasons": dict(invalid_reasons),
        "filtered_reasons": dict(filtered_reasons),
        "sequence_gaps": dict(gaps),
        "duplicates_or_reordered": dict(reordered),
    }
    if args.event_at is not None:
        if event_offset_actual is None:
            print("RESULT=FAIL_EVENT_NOT_REACHED", file=sys.stderr)
            return 5
        metadata["event_offset_seconds"] = event_offset_actual
        metadata["event_label"] = args.activity
        metadata["window_policy"] = "event_centered"
    else:
        metadata["window_policy"] = "sliding"

    tmp_capture = capture_path.with_suffix(".tmp.npz")
    np.savez_compressed(
        tmp_capture,
        meta_json=np.asarray(json.dumps(metadata, ensure_ascii=False)),
        iq=np.stack(iq_frames).astype(np.int8, copy=False),
        received_unix_ns=np.asarray(received_unix_ns, dtype=np.int64),
        received_monotonic_ns=np.asarray(received_monotonic_ns, dtype=np.int64),
        sender_ip=np.asarray(sender_ip),
        sender_port=np.asarray(sender_port, dtype=np.uint16),
        node_id=np.asarray(node_id, dtype=np.uint8),
        sequence=np.asarray(sequence, dtype=np.uint32),
        frequency_mhz=np.asarray(frequency_mhz, dtype=np.uint32),
        rssi_dbm=np.asarray(rssi_dbm, dtype=np.int8),
        noise_floor_dbm=np.asarray(noise_floor_dbm, dtype=np.int8),
        ppdu=np.asarray(ppdu, dtype=np.uint8),
        flags=np.asarray(flags, dtype=np.uint8),
        packet_size=np.asarray(packet_size, dtype=np.uint16),
        trailing_bytes=np.asarray(trailing_bytes, dtype=np.uint16),
        source_subcarriers=np.asarray(source_subcarriers, dtype=np.uint16),
    )
    os.replace(tmp_capture, capture_path)

    summary = {
        **metadata,
        "capture_file": capture_path.name,
        "capture_bytes": capture_path.stat().st_size,
    }
    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    low_rate_nodes = [
        node for node in args.nodes if valid_by_node[node] / elapsed < args.min_pps_per_node
    ]
    print(f"CAPTURE_FILE={capture_path.resolve()}")
    print(f"SUMMARY_FILE={summary_path.resolve()}")
    print(f"FRAMES={len(iq_frames)} PPS_BY_NODE={rates}")
    print(f"RAW_SUBCARRIER_COUNTS={dict(sorted(raw_subcarrier_counts.items()))}")
    print(f"INVALID_REASONS={dict(invalid_reasons)}")
    print(f"SEQUENCE_GAPS={dict(gaps)}")
    if low_rate_nodes:
        print(f"RESULT=FAIL_LOW_RATE nodes={low_rate_nodes}", file=sys.stderr)
        return 4
    print("RESULT=PASS_LABELED_CAPTURE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

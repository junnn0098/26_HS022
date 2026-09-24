"""Capture one labelled cough/overnight-confounder LLTF64 session."""

from __future__ import annotations

import argparse
import json
import signal
import socket
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from .adr018 import LTF_SELECTION_POLICY, extract_lltf_iq, parse_adr018
from .capture_labeled import parse_nodes, parse_participants, safe_name
from .health_labels import HEALTH_EVENT_LABELS, TIMED_HEALTH_EVENTS, validate_health_label


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Capture labelled LLTF64 health events for cough classification"
    )
    parser.add_argument("--label", required=True, choices=HEALTH_EVENT_LABELS)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--session", required=True)
    parser.add_argument("--participants", type=parse_participants, default=())
    parser.add_argument("--people", type=int, default=1)
    parser.add_argument("--room", default="room01")
    parser.add_argument("--notes", default="")
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5005)
    parser.add_argument("--nodes", type=parse_nodes, default=(1, 2, 3, 4))
    parser.add_argument("--subcarriers", type=int, default=64, choices=(64,))
    parser.add_argument("--duration", type=float, default=12.0)
    parser.add_argument("--countdown", type=int, default=5)
    parser.add_argument(
        "--event-at",
        type=float,
        default=6.0,
        help="Seconds after capture start for the prompted event",
    )
    parser.add_argument("--output-dir", type=Path, default=Path("captures_health"))
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    validate_health_label(args.label)
    if args.people < 1:
        parser.error("health-event captures require --people >= 1")
    if args.duration < 4.0:
        parser.error("duration must be at least 4 seconds")
    if args.label in TIMED_HEALTH_EVENTS and not 1.0 <= args.event_at <= args.duration - 1.0:
        parser.error("timed event requires event-at between 1 and duration-1")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    stop_requested = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind((args.bind, args.port))
    sock.settimeout(0.05)
    print(
        f"HEALTH_CAPTURE_ARMED bind={args.bind}:{args.port} label={args.label} "
        f"people={args.people} nodes={args.nodes}",
        flush=True,
    )
    for remaining in range(args.countdown, 0, -1):
        print(f"START_IN={remaining}", flush=True)
        time.sleep(1)
    dropped = 0
    sock.setblocking(False)
    while True:
        try:
            sock.recvfrom(65535)
            dropped += 1
        except BlockingIOError:
            break
    sock.setblocking(True)
    sock.settimeout(0.05)
    print(f"COUNTDOWN_BACKLOG_DROPPED={dropped}", flush=True)
    print("CAPTURE_STARTED", flush=True)

    timestamps: list[int] = []
    node_ids: list[int] = []
    iq_frames: list[np.ndarray] = []
    rssi_values: list[int] = []
    sequences: list[int] = []
    raw_widths: list[int] = []
    invalid: Counter[str] = Counter()
    by_node: Counter[int] = Counter()
    started = time.monotonic()
    event_announced = False
    next_print = started + 3.0
    try:
        while not stop_requested and time.monotonic() - started < args.duration:
            elapsed = time.monotonic() - started
            if (
                args.label in TIMED_HEALTH_EVENTS
                and not event_announced
                and elapsed >= args.event_at
            ):
                print(f"EVENT_GO={args.label}", flush=True)
                event_announced = True
            try:
                data, _sender = sock.recvfrom(65535)
            except socket.timeout:
                continue
            try:
                frame = parse_adr018(data)
                if frame.node_id not in args.nodes:
                    continue
                canonical = extract_lltf_iq(frame, args.subcarriers)
            except ValueError as exc:
                invalid[str(exc).split(":", 1)[0]] += 1
                continue
            timestamps.append(time.monotonic_ns())
            node_ids.append(frame.node_id)
            iq_frames.append(canonical)
            rssi_values.append(frame.rssi_dbm)
            sequences.append(frame.sequence)
            raw_widths.append(frame.subcarriers)
            by_node[frame.node_id] += 1
            if time.monotonic() >= next_print:
                print(
                    f"LIVE elapsed={elapsed:.1f}s frames={len(iq_frames)} nodes={dict(by_node)} "
                    f"invalid={sum(invalid.values())}",
                    flush=True,
                )
                next_print += 3.0
    finally:
        sock.close()

    elapsed = max(time.monotonic() - started, 1e-9)
    if not iq_frames:
        print("RESULT=FAIL_NO_LLTF64_FRAMES")
        return 2
    missing = [node for node in args.nodes if by_node[node] < max(10, args.duration * 10)]
    if missing:
        print(f"RESULT=FAIL_MISSING_OR_SLOW_NODES nodes={missing}")
        return 3
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    stem = (
        f"{timestamp}_{safe_name(args.label)}_p{args.people}_"
        f"{safe_name(args.subject)}_{safe_name(args.session)}"
    )
    capture_path = args.output_dir / f"{stem}.npz"
    summary_path = args.output_dir / f"{stem}.summary.json"
    metadata = {
        "schema": "hanium.ruview.health-capture.v1",
        "label": args.label,
        "subject": args.subject,
        "participants": list(args.participants) or [args.subject],
        "people_actual": args.people,
        "session": args.session,
        "room": args.room,
        "notes": args.notes,
        "expected_nodes": list(args.nodes),
        "canonical_subcarriers": args.subcarriers,
        "selected_ltf": "LLTF",
        "ltf_selection_policy": LTF_SELECTION_POLICY,
        "capture_elapsed_seconds": elapsed,
        "event_offset_seconds": args.event_at if args.label in TIMED_HEALTH_EVENTS else None,
        "valid_frames": len(iq_frames),
        "pps_by_node": {str(node): by_node[node] / elapsed for node in args.nodes},
        "invalid_reasons": dict(invalid),
    }
    np.savez_compressed(
        capture_path,
        received_monotonic_ns=np.asarray(timestamps, dtype=np.int64),
        node_id=np.asarray(node_ids, dtype=np.uint8),
        iq=np.stack(iq_frames).astype(np.int8, copy=False),
        rssi_dbm=np.asarray(rssi_values, dtype=np.int8),
        sequence=np.asarray(sequences, dtype=np.uint32),
        raw_subcarriers=np.asarray(raw_widths, dtype=np.uint16),
        meta_json=np.asarray(json.dumps(metadata, ensure_ascii=False)),
    )
    summary = {
        "file": str(capture_path),
        "label": args.label,
        "frames": len(iq_frames),
        "duration_seconds": round(elapsed, 3),
        "pps_by_node": {str(node): round(by_node[node] / elapsed, 3) for node in args.nodes},
        "iq_shape": list(np.stack(iq_frames).shape),
        "invalid_reasons": dict(invalid),
    }
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"CAPTURE_FILE={capture_path.resolve()}")
    print(f"SUMMARY_FILE={summary_path.resolve()}")
    print("RESULT=PASS_HEALTH_CAPTURE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


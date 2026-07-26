#!/usr/bin/env python3
"""Jetson Orin edge client for the Hanium safety app.

This script is the bridge between the edge device and the local demo server.

Current use:
  Jetson Orin -> POST /sensor/update -> Node.js server -> WebSocket -> Flutter app

It intentionally uses only the Python standard library so it can run on a
fresh Jetson setup without installing requests or other packages.

Typical commands:
  python3 jetson_edge_client.py sequence --server-url http://127.0.0.1:8000
  python3 jetson_edge_client.py once --event danger --server-url http://192.168.0.15:8000
  python3 jetson_edge_client.py stdin-json --server-url http://192.168.0.15:8000
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any


DEFAULT_SERVER_URL = os.environ.get("HANIUM_SERVER_URL", "http://127.0.0.1:8000")
DEFAULT_HOLD_MS = 60_000


@dataclass(frozen=True)
class EventPreset:
    x: float
    y: float
    status: str
    pose: str
    confidence: float


EVENT_PRESETS: dict[str, EventPreset] = {
    # living room, normal standing state
    "normal": EventPreset(x=0.35, y=0.45, status="normal", pose="standing", confidence=0.88),
    # entrance / going out warning
    "out": EventPreset(x=0.76, y=0.68, status="out", pose="walking", confidence=0.88),
    # bedroom stillness warning
    "still": EventPreset(x=0.31, y=0.68, status="still", pose="sitting", confidence=0.83),
    # fall suspicion danger
    "danger": EventPreset(x=0.36, y=0.45, status="danger", pose="lying", confidence=0.91),
}


LABEL_TO_EVENT = {
    "normal": "normal",
    "safe": "normal",
    "standing": "normal",
    "walk": "out",
    "walking": "out",
    "out": "out",
    "entrance": "out",
    "still": "still",
    "sitting": "still",
    "no_motion": "still",
    "fall": "danger",
    "fallen": "danger",
    "danger": "danger",
    "lying": "danger",
}


DEMO_SEQUENCE: list[tuple[str, dict[str, Any], float]] = [
    ("normal: living room", {"event": "normal", "x": 0.35, "y": 0.45}, 4.0),
    ("moving: living room", {"event": "normal", "x": 0.45, "y": 0.52, "pose": "walking"}, 2.0),
    ("moving: hallway", {"event": "normal", "x": 0.58, "y": 0.62, "pose": "walking"}, 2.0),
    ("warning: entrance access", {"event": "out"}, 5.0),
    ("warning: long stillness", {"event": "still"}, 5.0),
    ("danger: fall suspicion", {"event": "danger"}, 8.0),
    ("recovery: normal", {"event": "normal"}, 4.0),
]


def clamp(value: float, minimum: float = 0.0, maximum: float = 1.0) -> float:
    return max(minimum, min(maximum, value))


def normalize_server_url(server_url: str) -> str:
    return server_url.rstrip("/")


def post_json(server_url: str, path: str, payload: dict[str, Any], timeout: float, retries: int) -> dict[str, Any]:
    url = f"{normalize_server_url(server_url)}{path}"
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    last_error: Exception | None = None
    for attempt in range(1, retries + 2):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                text = response.read().decode("utf-8")
                return json.loads(text) if text else {}
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_error = exc
            if attempt <= retries:
                print(f"[warn] request failed, retry {attempt}/{retries}: {exc}", file=sys.stderr)
                time.sleep(min(1.0 * attempt, 3.0))
            else:
                break

    raise RuntimeError(f"POST {url} failed: {last_error}") from last_error


def get_json(server_url: str, path: str, timeout: float) -> dict[str, Any]:
    url = f"{normalize_server_url(server_url)}{path}"
    with urllib.request.urlopen(url, timeout=timeout) as response:
        text = response.read().decode("utf-8")
        return json.loads(text) if text else {}


def build_payload(
    event: str,
    *,
    x: float | None = None,
    y: float | None = None,
    status: str | None = None,
    pose: str | None = None,
    confidence: float | None = None,
    room: str | None = None,
    source: str = "jetson_orin",
    hold_ms: int = DEFAULT_HOLD_MS,
) -> dict[str, Any]:
    preset = EVENT_PRESETS.get(event, EVENT_PRESETS["normal"])
    payload: dict[str, Any] = {
        "x": round(clamp(float(x if x is not None else preset.x)), 3),
        "y": round(clamp(float(y if y is not None else preset.y)), 3),
        "status": status or preset.status,
        "pose": pose or preset.pose,
        "confidence": round(clamp(float(confidence if confidence is not None else preset.confidence)), 2),
        "source": source,
        "holdMs": int(hold_ms),
    }
    # Room is optional. If omitted, the server calculates it from x/y.
    # Omitting it avoids Korean encoding issues between Windows, Jetson, and Node terminals.
    if room:
        payload["room"] = room
    return payload


def event_from_label(label: str | None) -> str:
    if not label:
        return "normal"
    return LABEL_TO_EVENT.get(str(label).strip().lower(), "normal")


def payload_from_ai_record(record: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    label = record.get("label") or record.get("status") or record.get("prediction")
    event = event_from_label(str(label) if label is not None else None)
    preset = EVENT_PRESETS[event]
    return build_payload(
        event,
        x=record.get("x", preset.x),
        y=record.get("y", preset.y),
        status=record.get("status", preset.status),
        pose=record.get("pose", preset.pose),
        confidence=record.get("confidence", record.get("probability", preset.confidence)),
        room=record.get("room"),
        source=args.source,
        hold_ms=args.hold_ms,
    )


def send_update(args: argparse.Namespace, payload: dict[str, Any]) -> dict[str, Any]:
    if args.dry_run:
        print(json.dumps({"dryRun": True, "payload": payload}, ensure_ascii=False, indent=2))
        return {"status": "dry_run", "payload": payload}

    result = post_json(
        args.server_url,
        "/sensor/update",
        payload,
        timeout=args.timeout,
        retries=args.retries,
    )
    return result


def print_result(name: str, payload: dict[str, Any], result: dict[str, Any]) -> None:
    location = result.get("location", payload)
    print(
        "[sent]",
        name,
        f"status={location.get('status')}",
        f"pose={location.get('pose')}",
        f"x={location.get('x')}",
        f"y={location.get('y')}",
        f"confidence={location.get('confidence')}",
    )


def command_health(args: argparse.Namespace) -> int:
    try:
        result = get_json(args.server_url, "/health", timeout=args.timeout)
    except Exception as exc:  # noqa: BLE001 - CLI should print the raw connection issue.
        print(f"[fail] server is not reachable: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def command_once(args: argparse.Namespace) -> int:
    event = args.event
    payload = build_payload(
        event,
        x=args.x,
        y=args.y,
        status=args.status,
        pose=args.pose,
        confidence=args.confidence,
        room=args.room,
        source=args.source,
        hold_ms=args.hold_ms,
    )
    result = send_update(args, payload)
    print_result(event, payload, result)
    return 0


def command_sequence(args: argparse.Namespace) -> int:
    print(f"[info] server={args.server_url}")
    print("[info] mode=sequence, Ctrl+C to stop")
    try:
        while True:
            for name, options, wait_seconds in DEMO_SEQUENCE:
                event = str(options.get("event", "normal"))
                preset = EVENT_PRESETS[event]
                payload = build_payload(
                    event,
                    x=options.get("x", preset.x),
                    y=options.get("y", preset.y),
                    status=options.get("status", preset.status),
                    pose=options.get("pose", preset.pose),
                    confidence=options.get("confidence", preset.confidence),
                    source=args.source,
                    hold_ms=args.hold_ms,
                )
                result = send_update(args, payload)
                print_result(name, payload, result)
                time.sleep(args.interval if args.interval is not None else wait_seconds)
            if not args.loop:
                break
    except KeyboardInterrupt:
        print("\n[info] stopped")
    return 0


def command_heartbeat(args: argparse.Namespace) -> int:
    print(f"[info] server={args.server_url}")
    print("[info] mode=heartbeat normal state, Ctrl+C to stop")
    try:
        while True:
            payload = build_payload("normal", source=args.source, hold_ms=args.hold_ms)
            result = send_update(args, payload)
            print_result("heartbeat", payload, result)
            time.sleep(args.interval or 10.0)
    except KeyboardInterrupt:
        print("\n[info] stopped")
    return 0


def command_stdin_json(args: argparse.Namespace) -> int:
    print("[info] reading JSON lines from stdin", file=sys.stderr)
    print('[info] example: {"label":"fall","confidence":0.92,"x":0.36,"y":0.45}', file=sys.stderr)
    for line_number, line in enumerate(sys.stdin, start=1):
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
            if not isinstance(record, dict):
                raise ValueError("JSON line must be an object")
            payload = payload_from_ai_record(record, args)
            result = send_update(args, payload)
            print_result(f"stdin:{line_number}", payload, result)
        except Exception as exc:  # noqa: BLE001 - keep streaming even if one record is bad.
            print(f"[error] line {line_number}: {exc}", file=sys.stderr)
            if args.stop_on_error:
                return 1
    return 0


def add_common_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--server-url", default=DEFAULT_SERVER_URL, help="Local server URL. Default: %(default)s")
    parser.add_argument("--source", default="jetson_orin", help="Value sent as payload.source")
    parser.add_argument("--hold-ms", type=int, default=DEFAULT_HOLD_MS, help="How long the server should hold this state")
    parser.add_argument("--timeout", type=float, default=5.0, help="HTTP timeout seconds")
    parser.add_argument("--retries", type=int, default=2, help="Retry count for failed POST requests")
    parser.add_argument("--dry-run", action="store_true", help="Print payloads without sending them")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Jetson Orin edge client for Hanium local server")
    subparsers = parser.add_subparsers(dest="command", required=True)

    health = subparsers.add_parser("health", help="Check server /health")
    add_common_options(health)
    health.set_defaults(func=command_health)

    once = subparsers.add_parser("once", help="Send one event")
    add_common_options(once)
    once.add_argument("--event", choices=sorted(EVENT_PRESETS), default="normal")
    once.add_argument("--x", type=float)
    once.add_argument("--y", type=float)
    once.add_argument("--status", choices=["normal", "out", "danger", "still"])
    once.add_argument("--pose", choices=["standing", "walking", "lying", "sitting"])
    once.add_argument("--confidence", type=float)
    once.add_argument("--room", help="Optional room name. Usually omit this and let the server calculate from x/y.")
    once.set_defaults(func=command_once)

    sequence = subparsers.add_parser("sequence", help="Run demo sequence: normal -> out -> still -> danger")
    add_common_options(sequence)
    sequence.add_argument("--interval", type=float, help="Override wait seconds between sequence steps")
    sequence.add_argument("--loop", action="store_true", help="Repeat the sequence forever")
    sequence.set_defaults(func=command_sequence)

    heartbeat = subparsers.add_parser("heartbeat", help="Keep sending normal state")
    add_common_options(heartbeat)
    heartbeat.add_argument("--interval", type=float, default=10.0)
    heartbeat.set_defaults(func=command_heartbeat)

    stdin_json = subparsers.add_parser("stdin-json", help="Read AI prediction JSON lines from stdin")
    add_common_options(stdin_json)
    stdin_json.add_argument("--stop-on-error", action="store_true")
    stdin_json.set_defaults(func=command_stdin_json)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())

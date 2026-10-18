#!/usr/bin/env python3
"""Jetson Orin edge client for the Hanium safety app.

This script is the bridge between the edge device and the local demo server.

Current use:
  Jetson Orin -> POST /sensor/update -> Node.js server -> WebSocket -> Flutter app

It intentionally uses only the Python standard library so it can run on a
fresh Jetson setup without installing requests or other packages.

Typical commands:
  # Real pipeline: forward edge_ai live inference results to the server
  python3 jetson_edge_client.py live-status --status-file ../../edge_ai/runtime/latest_status.json --server-url http://192.168.0.15:8000
  python3 jetson_edge_client.py live-status --status-url http://<jetson-ip>:8080/status --server-url http://127.0.0.1:8000
  ./edge_ai/jetson/run_live.sh | python3 jetson_edge_client.py stdin-json --server-url http://192.168.0.15:8000

  # Demo / test helpers (preset values, sent with source=scripted_demo)
  python3 jetson_edge_client.py sequence --server-url http://127.0.0.1:8000
  python3 jetson_edge_client.py once --event danger --server-url http://192.168.0.15:8000

If the server was started with HANIUM_API_TOKEN, set the same environment variable
here (or pass --server-token) so requests carry `Authorization: Bearer <token>`.
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
DEFAULT_SERVER_TOKEN = os.environ.get("HANIUM_API_TOKEN", "")
DEFAULT_HOLD_MS = 60_000
LIVE_HOLD_MS = 15_000
LIVE_STATUS_PREFIX = "LIVE_STATUS="
LIVE_STATUS_SCHEMA_PREFIX = "hanium.ruview.live-status"
DEFAULT_STATUS_FILE = os.environ.get("RUVIEW_STATUS_FILE", "runtime/latest_status.json")
DEFAULT_MAX_AGE_SECONDS = 10.0

# Real edge inference results vs. preset/scripted demo input (shown differently in the app).
LIVE_SOURCE = "jetson_orin"
SCRIPTED_SOURCE = "scripted_demo"

# fall.state values of edge_ai's FallStateMachine that are a real (non-alarm) judgement.
# Anything else (model_unavailable, unknown, missing) is forwarded as status=unknown.
KNOWN_FALL_STATES = {"normal", "fall_candidate", "post_fall_check", "confirmed", "recovered"}

# edge_ai display activities -> app pose
LIVE_ACTIVITY_TO_POSE = {
    "walking": "walking",
    "sitting": "sitting",
    "lying": "lying",
    "fall": "lying",
    "still": "standing",
}


@dataclass(frozen=True)
class EventPreset:
    x: float
    y: float
    status: str
    pose: str
    confidence: float
    breathing_rate: float
    breathing_confidence: float


EVENT_PRESETS: dict[str, EventPreset] = {
    # living room, normal standing state
    "normal": EventPreset(
        x=0.35,
        y=0.45,
        status="normal",
        pose="standing",
        confidence=0.88,
        breathing_rate=16.8,
        breathing_confidence=0.84,
    ),
    # entrance / going out warning
    "out": EventPreset(
        x=0.76,
        y=0.68,
        status="out",
        pose="walking",
        confidence=0.88,
        breathing_rate=18.4,
        breathing_confidence=0.82,
    ),
    # bedroom stillness warning
    "still": EventPreset(
        x=0.31,
        y=0.68,
        status="still",
        pose="sitting",
        confidence=0.83,
        breathing_rate=13.6,
        breathing_confidence=0.78,
    ),
    # fall suspicion danger
    "danger": EventPreset(
        x=0.36,
        y=0.45,
        status="danger",
        pose="lying",
        confidence=0.91,
        breathing_rate=24.1,
        breathing_confidence=0.84,
    ),
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


def json_headers(token: str = "") -> dict[str, str]:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def post_json(
    server_url: str,
    path: str,
    payload: dict[str, Any],
    timeout: float,
    retries: int,
    token: str = "",
) -> dict[str, Any]:
    url = f"{normalize_server_url(server_url)}{path}"
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers=json_headers(token),
        method="POST",
    )

    last_error: Exception | None = None
    for attempt in range(1, retries + 2):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                text = response.read().decode("utf-8")
                return json.loads(text) if text else {}
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            if isinstance(exc, urllib.error.HTTPError) and 400 <= exc.code < 500:
                # Client errors (e.g. 401 missing token, 415) do not get better by retrying.
                hint = " (set HANIUM_API_TOKEN or --server-token)" if exc.code == 401 else ""
                raise RuntimeError(f"POST {url} was rejected: HTTP {exc.code}{hint}") from exc
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
    breathing_rate: float | None = None,
    breathing_confidence: float | None = None,
    room: str | None = None,
    source: str = SCRIPTED_SOURCE,
    hold_ms: int = DEFAULT_HOLD_MS,
) -> dict[str, Any]:
    preset = EVENT_PRESETS.get(event, EVENT_PRESETS["normal"])
    payload: dict[str, Any] = {
        "x": round(clamp(float(x if x is not None else preset.x)), 3),
        "y": round(clamp(float(y if y is not None else preset.y)), 3),
        "status": status or preset.status,
        "pose": pose or preset.pose,
        "confidence": round(clamp(float(confidence if confidence is not None else preset.confidence)), 2),
        "breathingRate": round(
            clamp(float(breathing_rate if breathing_rate is not None else preset.breathing_rate), 6.0, 36.0),
            1,
        ),
        "breathingConfidence": round(
            clamp(
                float(
                    breathing_confidence
                    if breathing_confidence is not None
                    else preset.breathing_confidence
                )
            ),
            2,
        ),
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
    known_label = label is not None and str(label).strip().lower() in LABEL_TO_EVENT
    event = event_from_label(str(label) if label is not None else None)
    preset = EVENT_PRESETS[event]
    breathing_rate = record.get("breathingRate", record.get("respirationRate", record.get("breathRate")))
    payload = build_payload(
        event,
        x=record.get("x", preset.x),
        y=record.get("y", preset.y),
        # A missing or unrecognized label is "unknown", never silently "normal".
        status=record.get("status", preset.status) if known_label else "unknown",
        pose=record.get("pose", preset.pose),
        confidence=record.get("confidence", record.get("probability", preset.confidence)),
        breathing_rate=breathing_rate,
        breathing_confidence=record.get(
            "breathingConfidence",
            record.get("respirationConfidence", preset.breathing_confidence),
        ),
        room=record.get("room"),
        source=args.source,
        hold_ms=args.hold_ms,
    )
    if breathing_rate is None:
        # Do not fill a missing breathing value with a preset; the app shows it as waiting.
        payload.pop("breathingRate", None)
        payload.pop("breathingConfidence", None)
    return payload


def is_live_status(record: dict[str, Any]) -> bool:
    return str(record.get("schema", "")).startswith(LIVE_STATUS_SCHEMA_PREFIX)


def payload_from_live_status(record: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    """Convert edge_ai `hanium.ruview.live-status.v2` output into a /sensor/update payload.

    - The fall state machine decides the alarm: only a CONFIRMED fall becomes `danger`.
    - `model_unavailable`, `unknown` or any unrecognized/missing fall state becomes
      `unknown`, so "no model / low quality" is never shown as `normal`.
    - The model senses one room and does not estimate coordinates, so the marker is
      placed at the monitored room's floor-plan position given by --room-x/--room-y.
    - Breathing rate is forwarded only when edge_ai reports a reliable estimate;
      otherwise it is omitted instead of being filled with a made-up number.
    """
    fall = record.get("fall") or {}
    fall_state = str(fall.get("state") or "").strip().lower()
    alarm = bool(fall.get("alarm")) or fall_state == "confirmed"
    activity = str(record.get("activity") or "unknown")
    probabilities = record.get("activity_probabilities") or {}

    if alarm:
        status, pose = "danger", "lying"
        confidence = probabilities.get("fall", record.get("activity_confidence"))
    else:
        status = "normal" if fall_state in KNOWN_FALL_STATES else "unknown"
        pose = LIVE_ACTIVITY_TO_POSE.get(activity, "standing")
        confidence = record.get("activity_confidence")

    payload: dict[str, Any] = {
        "x": round(clamp(float(args.room_x)), 3),
        "y": round(clamp(float(args.room_y)), 3),
        "status": status,
        "pose": pose,
        "source": args.source,
        "holdMs": int(args.hold_ms),
    }
    if confidence is not None:
        payload["confidence"] = round(clamp(float(confidence)), 2)

    respiratory = (record.get("health") or {}).get("respiratory") or {}
    breathing_rate = respiratory.get("breathing_rate_bpm")
    if breathing_rate is not None:
        payload["breathingRate"] = round(clamp(float(breathing_rate), 6.0, 36.0), 1)
        breathing_confidence = respiratory.get("breathing_confidence")
        if breathing_confidence is not None:
            payload["breathingConfidence"] = round(clamp(float(breathing_confidence)), 2)
    return payload


def live_status_age(record: dict[str, Any], now: float | None = None) -> float | None:
    """Seconds since the record's `unix_time`, or None when it has no usable timestamp."""
    try:
        recorded_at = float(record.get("unix_time"))
    except (TypeError, ValueError):
        return None
    return (time.time() if now is None else now) - recorded_at


def is_stale_live_status(record: dict[str, Any], max_age: float, now: float | None = None) -> bool:
    """A record older than `max_age` seconds (or without `unix_time`) is stale. max_age <= 0 disables."""
    if max_age <= 0:
        return False
    age = live_status_age(record, now)
    return age is None or age > max_age


def stale_payload(args: argparse.Namespace) -> dict[str, Any]:
    """Tell the server the edge result is no longer current instead of holding the last state."""
    return {
        "x": round(clamp(float(args.room_x)), 3),
        "y": round(clamp(float(args.room_y)), 3),
        "status": "unknown",
        "pose": "standing",
        "source": args.source,
        "holdMs": int(args.hold_ms),
    }


def parse_json_line(line: str) -> dict[str, Any] | None:
    """Parse one stdin line. Accepts plain JSON or edge_ai's `LIVE_STATUS=` lines."""
    line = line.strip()
    if line.startswith(LIVE_STATUS_PREFIX):
        line = line[len(LIVE_STATUS_PREFIX):]
    if not line.startswith("{"):
        return None  # other log lines from run_live.sh
    record = json.loads(line)
    if not isinstance(record, dict):
        raise ValueError("JSON line must be an object")
    return record


def read_live_status(args: argparse.Namespace) -> dict[str, Any]:
    if args.status_url:
        headers = {"Accept": "application/json"}
        if args.token:
            headers["Authorization"] = f"Bearer {args.token}"
        request = urllib.request.Request(args.status_url, headers=headers, method="GET")
        with urllib.request.urlopen(request, timeout=args.timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    with open(args.status_file, encoding="utf-8") as handle:
        return json.load(handle)


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
        token=args.server_token,
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
        f"breathingRate={location.get('breathingRate')}",
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
        breathing_rate=args.breathing_rate,
        breathing_confidence=args.breathing_confidence,
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
                    breathing_rate=options.get("breathingRate", preset.breathing_rate),
                    breathing_confidence=options.get(
                        "breathingConfidence",
                        preset.breathing_confidence,
                    ),
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


def command_live_status(args: argparse.Namespace) -> int:
    source = args.status_url or args.status_file
    print(f"[info] server={args.server_url}")
    print(f"[info] mode=live-status, reading {source} every {args.interval}s, Ctrl+C to stop")
    if args.max_age > 0:
        print(f"[info] records older than {args.max_age}s are rejected as stale (--max-age)")
    last_seen: Any = object()
    stale_reported = False
    exit_code = 0
    try:
        while True:
            try:
                record = read_live_status(args)
            except FileNotFoundError:
                print(f"[wait] {source} not found yet; is run_live.sh running?", file=sys.stderr)
            except Exception as exc:  # noqa: BLE001 - keep polling through transient errors.
                print(f"[error] could not read live status: {exc}", file=sys.stderr)
            else:
                if not is_live_status(record):
                    print("[error] not a hanium.ruview.live-status payload", file=sys.stderr)
                elif is_stale_live_status(record, args.max_age):
                    # Do not forward an old judgement as current; report "unknown" once instead.
                    exit_code = 1
                    if not stale_reported:
                        age = live_status_age(record)
                        age_text = "no unix_time" if age is None else f"{age:.1f}s old"
                        print(
                            f"[stale] live status rejected ({age_text}, limit {args.max_age}s); "
                            "sending status=unknown. Is run_live.sh still running? "
                            "If the Jetson and PC clocks differ, sync them or use --max-age 0.",
                            file=sys.stderr,
                        )
                        try:
                            send_update(args, stale_payload(args))
                            stale_reported = True
                        except Exception as exc:  # noqa: BLE001
                            print(f"[error] could not send to server: {exc}", file=sys.stderr)
                elif record.get("unix_time") != last_seen:
                    last_seen = record.get("unix_time")
                    stale_reported = False
                    exit_code = 0
                    payload = payload_from_live_status(record, args)
                    try:
                        result = send_update(args, payload)
                        print_result(f"live:{record.get('fall', {}).get('state', '-')}", payload, result)
                    except Exception as exc:  # noqa: BLE001
                        print(f"[error] could not send to server: {exc}", file=sys.stderr)
            if args.once:
                return exit_code
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\n[info] stopped")
    return 0


def command_stdin_json(args: argparse.Namespace) -> int:
    print("[info] reading JSON lines from stdin", file=sys.stderr)
    print('[info] example: {"label":"fall","confidence":0.92,"x":0.36,"y":0.45}', file=sys.stderr)
    print("[info] edge_ai LIVE_STATUS= lines are also accepted", file=sys.stderr)
    for line_number, line in enumerate(sys.stdin, start=1):
        try:
            record = parse_json_line(line)
            if record is None:
                continue
            if is_live_status(record):
                payload = payload_from_live_status(record, args)
            else:
                payload = payload_from_ai_record(record, args)
            result = send_update(args, payload)
            print_result(f"stdin:{line_number}", payload, result)
        except Exception as exc:  # noqa: BLE001 - keep streaming even if one record is bad.
            print(f"[error] line {line_number}: {exc}", file=sys.stderr)
            if args.stop_on_error:
                return 1
    return 0


def add_common_options(parser: argparse.ArgumentParser, source: str = SCRIPTED_SOURCE) -> None:
    parser.add_argument("--server-url", default=DEFAULT_SERVER_URL, help="Local server URL. Default: %(default)s")
    parser.add_argument(
        "--server-token",
        default=DEFAULT_SERVER_TOKEN,
        help="Bearer token for the local server (default: env HANIUM_API_TOKEN)",
    )
    parser.add_argument("--source", default=source, help="Value sent as payload.source. Default: %(default)s")
    parser.add_argument("--hold-ms", type=int, default=DEFAULT_HOLD_MS, help="How long the server should hold this state")
    parser.add_argument("--timeout", type=float, default=5.0, help="HTTP timeout seconds")
    parser.add_argument("--retries", type=int, default=2, help="Retry count for failed POST requests")
    parser.add_argument("--dry-run", action="store_true", help="Print payloads without sending them")


def add_room_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--room-x",
        type=float,
        default=EVENT_PRESETS["normal"].x,
        help="Floor-plan x (0~1) of the monitored room where the sensor set is installed",
    )
    parser.add_argument(
        "--room-y",
        type=float,
        default=EVENT_PRESETS["normal"].y,
        help="Floor-plan y (0~1) of the monitored room where the sensor set is installed",
    )


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
    once.add_argument("--breathing-rate", type=float, help="Breaths per minute sent as breathingRate")
    once.add_argument("--breathing-confidence", type=float, help="Breathing signal confidence, 0.0~1.0")
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

    live = subparsers.add_parser(
        "live-status",
        help="Forward edge_ai live inference results (latest_status.json or status_api /status) to the server",
    )
    add_common_options(live, source=LIVE_SOURCE)
    add_room_options(live)
    live.add_argument("--status-file", default=DEFAULT_STATUS_FILE, help="edge_ai runtime/latest_status.json path")
    live.add_argument("--status-url", help="Read from status_api instead, e.g. http://<jetson-ip>:8080/status")
    live.add_argument("--token", default=os.environ.get("RUVIEW_API_TOKEN", ""), help="status_api bearer token")
    live.add_argument("--interval", type=float, default=1.0, help="Polling interval seconds")
    live.add_argument("--once", action="store_true", help="Read and send one status, then exit")
    live.add_argument(
        "--max-age",
        type=float,
        default=DEFAULT_MAX_AGE_SECONDS,
        help="Reject records whose unix_time is older than this many seconds (0 disables). Default: %(default)s",
    )
    live.set_defaults(func=command_live_status, hold_ms=LIVE_HOLD_MS)

    stdin_json = subparsers.add_parser("stdin-json", help="Read AI prediction JSON lines (or LIVE_STATUS= lines) from stdin")
    add_common_options(stdin_json, source=LIVE_SOURCE)
    add_room_options(stdin_json)
    stdin_json.add_argument("--stop-on-error", action="store_true")
    stdin_json.set_defaults(func=command_stdin_json)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())

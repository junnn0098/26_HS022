"""Small authenticated-optional HTTP API for the Flutter/desktop client."""

from __future__ import annotations

import argparse
import json
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


class StatusHandler(BaseHTTPRequestHandler):
    status_file: Path
    event_log: Path
    token: str

    def _authorized(self) -> bool:
        return not self.token or self.headers.get("Authorization") == f"Bearer {self.token}"

    def _json(self, status: int, payload: dict | list) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if not self._authorized():
            self._json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
            return
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            age = None
            if self.status_file.exists():
                age = max(0.0, time.time() - self.status_file.stat().st_mtime)
            self._json(
                HTTPStatus.OK,
                {
                    "status": "ok" if age is not None and age < 10 else "waiting",
                    "latest_status_age_seconds": age,
                },
            )
        elif parsed.path == "/status":
            if not self.status_file.exists():
                self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"status": "no inference yet"})
                return
            try:
                self._json(HTTPStatus.OK, json.loads(self.status_file.read_text(encoding="utf-8")))
            except Exception as exc:
                self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})
        elif parsed.path in {"/respiratory", "/coughs"}:
            if not self.status_file.exists():
                self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"status": "no monitoring result yet"})
                return
            try:
                status = json.loads(self.status_file.read_text(encoding="utf-8"))
                health = status.get("health", {})
                key = "respiratory" if parsed.path == "/respiratory" else "cough"
                payload = health.get(key)
                if payload is None:
                    self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"status": f"{key} not ready"})
                else:
                    self._json(HTTPStatus.OK, payload)
            except Exception as exc:
                self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})
        elif parsed.path == "/events":
            query = parse_qs(parsed.query)
            limit = min(200, max(1, int(query.get("limit", ["20"])[0])))
            if not self.event_log.exists():
                self._json(HTTPStatus.OK, [])
                return
            lines = self.event_log.read_text(encoding="utf-8").splitlines()[-limit:]
            events = []
            for line in lines:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
            self._json(HTTPStatus.OK, events)
        else:
            self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def log_message(self, format_string: str, *args: object) -> None:
        print(f"API {self.address_string()} {format_string % args}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Hanium live status API")
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--status-file", type=Path, default=Path("runtime/latest_status.json"))
    parser.add_argument("--event-log", type=Path, default=Path("runtime/events.jsonl"))
    parser.add_argument("--token", default="")
    args = parser.parse_args()
    StatusHandler.status_file = args.status_file
    StatusHandler.event_log = args.event_log
    StatusHandler.token = args.token
    server = ThreadingHTTPServer((args.bind, args.port), StatusHandler)
    print(f"STATUS_API_READY http://{args.bind}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

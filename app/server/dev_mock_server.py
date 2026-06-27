import base64
import hashlib
import json
import math
import random
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HOST = "0.0.0.0"
PORT = 8000
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

_tokens: list[str] = []


def _json_response(handler: BaseHTTPRequestHandler, status: int, body: dict):
    payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "*")
    handler.send_header("Access-Control-Allow-Headers", "*")
    handler.send_header("Content-Length", str(len(payload)))
    handler.end_headers()
    handler.wfile.write(payload)


def _room_from_position(x: float, y: float) -> str:
    if x > 0.62 and y < 0.42:
        return "주방"
    if x < 0.48 and y > 0.58:
        return "침실"
    if x > 0.68 and y > 0.55:
        return "현관"
    if 0.47 < x < 0.68 and y > 0.56:
        return "욕실"
    return "거실"


def _status_for_tick(tick: int) -> str:
    if tick % 45 in (21, 22, 23):
        return "danger"
    if tick % 36 in (10, 11, 12):
        return "out"
    return "normal"


def _pose_from_status(status: str) -> str:
    if status == "danger":
        return "lying"
    if status == "out":
        return "walking"
    return "standing"


def _next_location(tick: int) -> dict:
    angle = tick / 7
    x = 0.48 + math.cos(angle) * 0.22 + random.uniform(-0.015, 0.015)
    y = 0.50 + math.sin(angle * 0.8) * 0.24 + random.uniform(-0.015, 0.015)
    x = max(0.12, min(0.88, x))
    y = max(0.12, min(0.88, y))
    status = _status_for_tick(tick)
    return {
        "x": round(x, 3),
        "y": round(y, 3),
        "status": status,
        "room": _room_from_position(x, y),
        "pose": _pose_from_status(status),
        "confidence": 0.86,
        "timestamp": datetime.now().strftime("%H:%M:%S"),
    }


def _send_ws_text(sock, text: str):
    payload = text.encode("utf-8")
    header = bytearray([0x81])
    length = len(payload)
    if length < 126:
        header.append(length)
    elif length < 65536:
        header.append(126)
        header.extend(length.to_bytes(2, "big"))
    else:
        header.append(127)
        header.extend(length.to_bytes(8, "big"))
    sock.sendall(bytes(header) + payload)


class HaniumMockHandler(BaseHTTPRequestHandler):
    server_version = "HaniumMockServer/1.0"

    def log_message(self, format, *args):
        print("[%s] %s" % (datetime.now().strftime("%H:%M:%S"), format % args))

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/ws/location" and self.headers.get("Upgrade", "").lower() == "websocket":
            self._handle_websocket()
            return
        if path == "/":
            _json_response(
                self,
                200,
                {
                    "project": "Hanium CSI Safety System",
                    "status": "running",
                    "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                },
            )
            return
        if path == "/health":
            _json_response(self, 200, {"ok": True})
            return
        _json_response(self, 404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8"))
        except Exception:
            body = {}

        if path == "/device/register":
            token = body.get("token")
            if token and token not in _tokens:
                _tokens.append(token)
            _json_response(self, 200, {"status": "ok", "tokens": len(_tokens)})
            return

        if path == "/alarm/test":
            _json_response(self, 200, {"status": "sent", "recipients": len(_tokens)})
            return

        _json_response(self, 404, {"error": "not found"})

    def _handle_websocket(self):
        key = self.headers.get("Sec-WebSocket-Key")
        if not key:
            self.send_error(400, "Missing Sec-WebSocket-Key")
            return

        accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()

        tick = 0
        try:
            while True:
                _send_ws_text(self.request, json.dumps(_next_location(tick), ensure_ascii=False))
                tick += 1
                time.sleep(1)
        except (ConnectionError, OSError):
            pass


def main():
    server = ThreadingHTTPServer((HOST, PORT), HaniumMockHandler)
    print(f"Hanium mock server running on http://127.0.0.1:{PORT}")
    print("Android emulator app URL: http://10.0.2.2:8000")
    print("WebSocket endpoint: ws://10.0.2.2:8000/ws/location")
    server.serve_forever()


if __name__ == "__main__":
    main()

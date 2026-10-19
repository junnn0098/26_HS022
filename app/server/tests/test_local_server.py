"""Regression checks for local_server.js (stdlib only; needs Node.js on PATH).

Each test class copies the server into a temporary directory, so dev_state.json in
the checkout is never touched, and binds it to 127.0.0.1 on a free port.

    python -m unittest discover -s app/server/tests -v
"""

from __future__ import annotations

import base64
import json
import os
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

SERVER_DIR = Path(__file__).resolve().parents[1]
NODE = shutil.which("node")
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
HIDDEN_ROOM = "위치 공유 꺼짐"


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class LocalServer:
    def __init__(self, **extra_env: str) -> None:
        self._temp = tempfile.TemporaryDirectory(prefix="hanium-local-server-")
        directory = Path(self._temp.name)
        for name in ("local_server.js", "package.json"):
            shutil.copy(SERVER_DIR / name, directory / name)
        self.port = free_port()
        self.url = f"http://127.0.0.1:{self.port}"
        env = {key: os.environ[key] for key in ("PATH", "SYSTEMROOT", "WINDIR") if key in os.environ}
        env.update({"PORT": str(self.port), "HOST": "127.0.0.1", "REAL_SENSOR_ONLY": "true"}, **extra_env)
        self._log = (directory / "server.log").open("w", encoding="utf-8")
        self.process = subprocess.Popen(
            [NODE, "local_server.js"], cwd=directory, env=env, stdout=self._log, stderr=self._log
        )
        for _ in range(100):
            if self.process.poll() is not None:
                raise RuntimeError("local_server.js exited before becoming ready")
            try:
                self.request("GET", "/health")
                return
            except (urllib.error.URLError, ConnectionError):
                time.sleep(0.05)
        raise RuntimeError("local_server.js did not become ready")

    def request(self, method: str, path: str, body=None, headers: dict | None = None):
        headers = dict(headers or {})
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers.setdefault("Content-Type", "application/json")
        request = urllib.request.Request(self.url + path, data=data, headers=headers, method=method)
        try:
            with OPENER.open(request, timeout=5) as response:
                return response.status, response.headers, json.loads(response.read() or b"null")
        except urllib.error.HTTPError as exc:
            return exc.code, exc.headers, json.loads(exc.read() or b"null")

    def close(self) -> None:
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
        self._log.close()
        self._temp.cleanup()


class WebSocketReader:
    """Minimal client for the server's unmasked text frames."""

    def __init__(self, port: int, query: str = "", origin: str | None = None) -> None:
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        origin_header = f"Origin: {origin}\r\n" if origin else ""
        self.sock.sendall(
            (
                f"GET /ws/location{query} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
                "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                f"{origin_header}Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
            ).encode("ascii")
        )
        self.buffer = b""
        self._need_until(b"\r\n\r\n")
        head, self.buffer = self.buffer.split(b"\r\n\r\n", 1)
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise ConnectionError(head.decode("latin-1"))

    def _need_until(self, marker: bytes) -> None:
        while marker not in self.buffer:
            self._recv()

    def _need(self, size: int) -> None:
        while len(self.buffer) < size:
            self._recv()

    def _recv(self) -> None:
        chunk = self.sock.recv(4096)
        if not chunk:
            raise ConnectionError("WebSocket closed")
        self.buffer += chunk

    def read_json(self) -> dict:
        self._need(2)
        length, offset = self.buffer[1] & 0x7F, 2
        if length == 126:
            self._need(4)
            length, offset = int.from_bytes(self.buffer[2:4], "big"), 4
        elif length == 127:
            self._need(10)
            length, offset = int.from_bytes(self.buffer[2:10], "big"), 10
        self._need(offset + length)
        payload = self.buffer[offset : offset + length]
        self.buffer = self.buffer[offset + length :]
        return json.loads(payload.decode("utf-8"))

    def close(self) -> None:
        self.sock.close()


@unittest.skipIf(NODE is None, "node is not on PATH")
class LocalServerWithoutTokenTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = LocalServer()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.close()

    def post(self, path: str, body: dict):
        return self.server.request("POST", path, body)

    def test_websocket_respects_location_sharing_off(self) -> None:
        self.post("/sensor/update", {"x": 0.2, "y": 0.8, "status": "normal", "source": "scripted_demo"})
        self.post("/settings", {"locationSharingEnabled": False})
        try:
            reader = WebSocketReader(self.server.port)
            try:
                frames = [reader.read_json(), reader.read_json()]  # first send + one 1 s tick
            finally:
                reader.close()
            _, _, latest = self.server.request("GET", "/location/latest")
            for location in frames + [latest["location"]]:
                self.assertEqual(location["room"], HIDDEN_ROOM)
                self.assertEqual((location["x"], location["y"]), (0.5, 0.5))
                self.assertFalse(location["locationSharingEnabled"])
        finally:
            self.post("/settings", {"locationSharingEnabled": True})
        reader = WebSocketReader(self.server.port)
        try:
            visible = reader.read_json()
        finally:
            reader.close()
        self.assertEqual((visible["x"], visible["y"]), (0.2, 0.8))

    def test_missing_breathing_stays_null(self) -> None:
        _, _, result = self.post("/sensor/update", {"x": 0.35, "y": 0.45, "status": "normal", "source": "scripted_demo"})
        location = result["location"]
        self.assertIsNone(location["breathingRate"])
        self.assertIsNone(location["breathingConfidence"])
        self.assertFalse(location["breathingEstimated"])
        _, _, result = self.post("/sensor/update", {"x": 0.35, "y": 0.45, "status": "normal", "breathingRate": 18.2})
        self.assertEqual(result["location"]["breathingRate"], 18.2)

    def test_unknown_status_and_missing_source(self) -> None:
        _, _, before = self.server.request("GET", "/alerts")
        for raw in ("unknown", "model_unavailable", "no_such_status"):
            _, _, result = self.post("/sensor/update", {"x": 0.35, "y": 0.45, "status": raw})
            self.assertEqual(result["location"]["status"], "unknown", raw)
            self.assertEqual(result["location"]["source"], "unknown")
            self.assertEqual(result["location"]["confidence"], 0)
        # The 0 confidence of 'unknown' must not carry over to the next judged state.
        _, _, result = self.post("/sensor/update", {"x": 0.35, "y": 0.45, "status": "normal", "source": "admin"})
        self.assertGreater(result["location"]["confidence"], 0)
        _, _, after = self.server.request("GET", "/alerts")
        self.assertEqual(len(after["alerts"]), len(before["alerts"]))

    def test_post_json_route_requires_json_content_type(self) -> None:
        status, _, _ = self.server.request(
            "POST", "/sensor/update", {"x": 0.5, "y": 0.5, "status": "normal"}, {"Content-Type": "text/plain"}
        )
        self.assertEqual(status, 415)

    def test_status_output_has_no_secrets(self) -> None:
        _, _, health = self.server.request("GET", "/health")
        self.assertNotIn("credentialPath", health["push"])
        _, _, saved = self.post("/emergency-info", {"doorPassword": "0000"})
        self.assertNotIn("doorPassword", saved["emergencyInfo"])
        _, _, state = self.server.request("GET", "/state")
        self.assertNotIn("doorPassword", state["emergencyInfo"])

    def test_no_wildcard_cors(self) -> None:
        _, headers, _ = self.server.request("GET", "/health", headers={"Origin": "http://other.example"})
        self.assertIsNone(headers.get("Access-Control-Allow-Origin"))


@unittest.skipIf(NODE is None, "node is not on PATH")
class LocalServerInitialStatusTest(unittest.TestCase):
    """Before any input (boot) and right after /demo/reset the state is 'unknown', not 'normal'."""

    def setUp(self) -> None:
        self.server = None

    def tearDown(self) -> None:
        if self.server is not None:
            self.server.close()

    def assert_no_data_yet(self, location: dict, source: str) -> None:
        self.assertEqual(location["status"], "unknown")
        self.assertEqual(location["source"], source)
        self.assertEqual(location["confidence"], 0)
        self.assertIsNone(location["breathingRate"])

    def test_boot_and_reset_start_unknown(self) -> None:
        self.server = LocalServer()  # REAL_SENSOR_ONLY=true: nothing but input changes the state
        _, _, before = self.server.request("GET", "/alerts")
        _, _, latest = self.server.request("GET", "/location/latest")
        self.assert_no_data_yet(latest["location"], "boot")
        reader = WebSocketReader(self.server.port)
        try:
            frames = [reader.read_json(), reader.read_json()]  # first send + one 1 s tick
        finally:
            reader.close()
        for frame in frames:
            self.assert_no_data_yet(frame, "boot")
        _, _, after = self.server.request("GET", "/alerts")
        self.assertEqual(after["alerts"], before["alerts"], "boot 'unknown' must not create an alert")
        _, _, result = self.server.request(
            "POST", "/sensor/update", {"x": 0.35, "y": 0.45, "status": "normal", "source": "scripted_demo"}
        )
        self.assertEqual(result["location"]["status"], "normal")
        self.assertGreater(result["location"]["confidence"], 0)
        _, _, reset = self.server.request("POST", "/demo/reset")
        self.assert_no_data_yet(reset["location"], "reset")
        self.assertEqual(reset["alerts"], [])

    def test_mock_motion_replaces_boot_unknown(self) -> None:
        self.server = LocalServer(REAL_SENSOR_ONLY="false")  # sensor-less demo: mock motion ON
        reader = WebSocketReader(self.server.port)
        try:
            first, tick = reader.read_json(), reader.read_json()
        finally:
            reader.close()
        self.assert_no_data_yet(first, "boot")
        self.assertEqual(tick["source"], "mock")
        self.assertIn(tick["status"], ("normal", "out", "danger"))


@unittest.skipIf(NODE is None, "node is not on PATH")
class LocalServerWithTokenTest(unittest.TestCase):
    TOKEN = "unit-test-token"

    @classmethod
    def setUpClass(cls) -> None:
        cls.server = LocalServer(HANIUM_API_TOKEN=cls.TOKEN, HANIUM_CORS_ORIGIN="http://allowed.example")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.close()

    def test_token_required_only_on_protected_routes(self) -> None:
        auth = {"Authorization": f"Bearer {self.TOKEN}"}
        self.assertEqual(self.server.request("GET", "/health")[0], 200)
        self.assertEqual(self.server.request("GET", "/state")[0], 401)
        self.assertEqual(self.server.request("GET", "/emergency-info")[0], 401)
        self.assertEqual(self.server.request("GET", "/state", headers={"Authorization": "Bearer wrong"})[0], 401)
        self.assertEqual(self.server.request("GET", "/state", headers=auth)[0], 200)
        body = {"x": 0.5, "y": 0.5, "status": "normal", "source": "scripted_demo"}
        self.assertEqual(self.server.request("POST", "/sensor/update", body)[0], 401)
        self.assertEqual(self.server.request("POST", "/sensor/update", body, auth)[0], 200)

    def test_websocket_requires_token_and_known_origin(self) -> None:
        with self.assertRaises(ConnectionError):
            WebSocketReader(self.server.port)
        with self.assertRaises(ConnectionError):
            WebSocketReader(self.server.port, "?token=wrong")
        with self.assertRaises(ConnectionError):
            WebSocketReader(self.server.port, f"?token={self.TOKEN}", origin="http://evil.example")
        reader = WebSocketReader(self.server.port, f"?token={self.TOKEN}", origin="http://allowed.example")
        try:
            self.assertIn("status", reader.read_json())
        finally:
            reader.close()

    def test_cors_allowlist(self) -> None:
        _, headers, _ = self.server.request("GET", "/health", headers={"Origin": "http://allowed.example"})
        self.assertEqual(headers.get("Access-Control-Allow-Origin"), "http://allowed.example")
        _, headers, _ = self.server.request("GET", "/health", headers={"Origin": "http://other.example"})
        self.assertIsNone(headers.get("Access-Control-Allow-Origin"))


if __name__ == "__main__":
    unittest.main()

"""Check synthetic bridge/server behaviour against a temporary loopback-only local server.

local_server.js and package.json are copied unchanged into a temporary directory and
started with HOST=127.0.0.1, a free PORT and REAL_SENSOR_ONLY=true. App state and
credentials in the checkout are never copied. Every input is synthetic.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "app/server"
COPIED = ("local_server.js", "package.json")

# Expected behaviour of the current server and connection client.
EXPECTED = {
    "initial_status_before_input": "unknown",
    "confirmed_status": "danger",
    "provided_breathing_rate": 18.2,
    "provided_breathing_estimated_flag": False,
    "model_unavailable_forwarded_as": "unknown",
    "model_unavailable_server_status": "unknown",
    "missing_breathing_omitted_by_bridge": True,
    "missing_breathing_server_value": None,
    "missing_breathing_server_estimated_flag": False,
    "stale_unix_time_1_accepted": False,
    "stale_reported_by_cli": True,
    "stale_cli_exit_code": 1,
    "server_status_after_stale": "unknown",
}


def lf_sha256(path: Path) -> str:
    """SHA-256 of the content with CRLF normalised to LF, so Windows and Linux checkouts agree."""
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def live_status(unix_time: float, state: str, *, alarm: bool = False, breathing: dict | None = None) -> dict:
    record = {"schema": "hanium.ruview.live-status.v2", "unix_time": unix_time,
              "activity": "fall" if alarm else "unknown", "fall": {"state": state, "alarm": alarm},
              "health": {"respiratory": breathing or {}}}
    if alarm:
        record.update({"activity_confidence": 0.94, "activity_probabilities": {"fall": 0.94}})
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", default=shutil.which("node") or "node")
    parser.add_argument("--output", type=Path, default=ROOT / "experiments/results/local")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location("experiment_bridge", SERVER / "jetson_edge_client.py")
    bridge = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = bridge
    spec.loader.exec_module(bridge)
    with tempfile.TemporaryDirectory(prefix="hanium-bridge-") as directory:
        temp = Path(directory)
        # package.json pins CommonJS, so a parent package.json with "type": "module" cannot break require().
        for name in COPIED:
            shutil.copy(SERVER / name, temp / name)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        url = f"http://127.0.0.1:{port}"
        # No HANIUM_API_TOKEN, Firebase settings or user state reach the temporary server.
        env = {key: os.environ[key] for key in ("PATH", "SYSTEMROOT", "WINDIR") if key in os.environ}
        env.update({"PORT": str(port), "HOST": "127.0.0.1", "REAL_SENSOR_ONLY": "true"})
        # Do not use system proxy settings for local experiment traffic.
        http = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        log_path = temp / "server.log"
        with log_path.open("w", encoding="utf-8") as log:
            process = subprocess.Popen([args.node, "local_server.js"], cwd=temp, env=env, stdout=log, stderr=log)
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError("Temporary Node server exited before becoming ready:\n"
                                           + log_path.read_text(encoding="utf-8", errors="replace"))
                    try:
                        with http.open(url + "/health", timeout=0.3) as response:
                            json.load(response)
                        break
                    except (urllib.error.URLError, ConnectionError, TimeoutError):
                        time.sleep(0.05)
                else:
                    raise RuntimeError("Temporary Node server did not become ready.")
                options = bridge.build_parser().parse_args(["live-status", "--server-url", url, "--once"])

                def latest() -> dict:
                    with http.open(url + "/location/latest", timeout=3) as response:
                        return json.load(response)["location"]

                def post(record: dict) -> tuple[dict, dict]:
                    payload = bridge.payload_from_live_status(record, options)
                    request = urllib.request.Request(url + "/sensor/update", data=json.dumps(payload).encode(),
                                                     headers={"Content-Type": "application/json"}, method="POST")
                    with http.open(request, timeout=3) as response:
                        result = json.load(response)
                    return payload, result["location"]

                initial = latest()
                _, good = post(live_status(time.time(), "confirmed", alarm=True,
                                           breathing={"breathing_rate_bpm": 18.2, "breathing_confidence": 0.8}))
                missing_payload, missing = post(live_status(time.time(), "model_unavailable"))
                # A current 'normal' result, then an old one: the old result must not be forwarded as current.
                post(live_status(time.time(), "normal"))
                status_file = temp / "old_status.json"
                status_file.write_text(json.dumps(live_status(1, "normal")), encoding="utf-8")
                cli_env = dict(env, NO_PROXY="127.0.0.1,localhost", no_proxy="127.0.0.1,localhost",
                               PYTHONIOENCODING="utf-8")
                cli = subprocess.run([sys.executable, str(SERVER / "jetson_edge_client.py"), "live-status",
                                      "--server-url", url, "--status-file", str(status_file), "--once"],
                                     capture_output=True, text=True, encoding="utf-8", timeout=10, env=cli_env)
                after_stale = latest()
                observations = {
                    "initial_status_before_input": initial["status"],
                    "confirmed_status": good["status"],
                    "provided_breathing_rate": good["breathingRate"],
                    "provided_breathing_estimated_flag": good["breathingEstimated"],
                    "model_unavailable_forwarded_as": missing_payload["status"],
                    "model_unavailable_server_status": missing["status"],
                    "missing_breathing_omitted_by_bridge": "breathingRate" not in missing_payload,
                    "missing_breathing_server_value": missing["breathingRate"],
                    "missing_breathing_server_estimated_flag": missing["breathingEstimated"],
                    "stale_unix_time_1_accepted": cli.returncode == 0 and "[sent]" in cli.stdout,
                    "stale_reported_by_cli": "[stale]" in cli.stderr,
                    "stale_cli_exit_code": cli.returncode,
                    "server_status_after_stale": after_stale["status"],
                }
                checks = {key: observations[key] == value for key, value in EXPECTED.items()}
                sources = [SERVER / name for name in COPIED] + [SERVER / "jetson_edge_client.py", Path(__file__)]
                report = {
                    "scope": "Synthetic loopback HTTP only; no actual CSI, trained model, Flutter device or FCM.",
                    "executed_at": datetime.now().astimezone().isoformat(timespec="seconds"),
                    "python": platform.python_version(), "platform": platform.system(),
                    "node_version": subprocess.check_output([args.node, "--version"], text=True).strip(),
                    "hash_method": "SHA-256 of file content with CRLF normalised to LF; POSIX paths from the repository root",
                    "source_sha256": {p.relative_to(ROOT).as_posix(): lf_sha256(p) for p in sources},
                    "temporary_copy": "local_server.js and package.json copied unchanged; "
                                      "env HOST=127.0.0.1, free PORT, REAL_SENSOR_ONLY=true",
                    "expected": EXPECTED,
                    "observations": observations,
                    "checks": checks,
                    "all_checks_passed": all(checks.values()),
                }
                (args.output / "server_bridge.json").write_text(
                    json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                print(json.dumps(observations))
                failed = [key for key, ok in checks.items() if not ok]
                if failed:
                    print("[fail] " + ", ".join(failed), file=sys.stderr)
                return 0 if not failed else 1
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())

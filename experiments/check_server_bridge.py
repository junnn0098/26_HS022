"""Observe synthetic bridge/server behavior in a temporary loopback-only server."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
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
    source = (SERVER / "dev_mock_server.js").read_text(encoding="utf-8")
    binding = 'server.listen(PORT, "0.0.0.0",'
    if source.count(binding) != 1:
        raise RuntimeError("Server binding changed: review the loopback-only test harness before running.")
    # Only the disposable copy's listening address changes. App state and any
    # credentials in the checkout are never copied to the temporary directory.
    with tempfile.TemporaryDirectory(prefix="hanium-bridge-") as directory:
        temp = Path(directory)
        (temp / "server.js").write_text(source.replace(binding, 'server.listen(PORT, "127.0.0.1",'), encoding="utf-8")
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        url = f"http://127.0.0.1:{port}"
        env = {key: os.environ[key] for key in ("PATH", "SYSTEMROOT", "WINDIR") if key in os.environ}
        env.update({"PORT": str(port), "REAL_SENSOR_ONLY": "true"})
        # Do not use system proxy settings for local experiment traffic.
        http = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with (temp / "server.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen([args.node, str(temp / "server.js")], cwd=temp,
                                       env=env, stdout=log, stderr=log)
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError("Temporary Node server exited before becoming ready.")
                    try:
                        with http.open(url + "/health", timeout=0.3) as response:
                            json.load(response)
                        break
                    except (urllib.error.URLError, TimeoutError):
                        time.sleep(0.05)
                else:
                    raise RuntimeError("Temporary Node server did not become ready.")
                options = bridge.build_parser().parse_args(["live-status", "--server-url", url, "--once"])

                def post(record):
                    payload = bridge.payload_from_live_status(record, options)
                    request = urllib.request.Request(url + "/sensor/update", data=json.dumps(payload).encode(),
                                                     headers={"Content-Type": "application/json"}, method="POST")
                    with http.open(request, timeout=3) as response:
                        result = json.load(response)
                    return payload, result["location"]

                confirmed = {"schema": "hanium.ruview.live-status.v2", "unix_time": time.time(),
                             "activity": "fall", "activity_confidence": 0.94,
                             "activity_probabilities": {"fall": 0.94},
                             "fall": {"state": "confirmed", "alarm": True},
                             "health": {"respiratory": {"breathing_rate_bpm": 18.2, "breathing_confidence": 0.8}}}
                _, good = post(confirmed)
                unavailable = {"schema": "hanium.ruview.live-status.v2", "unix_time": 1,
                               "activity": "unknown", "fall": {"state": "model_unavailable", "alarm": False},
                               "health": {"respiratory": {}}}
                missing_payload, missing = post(unavailable)
                status_file = temp / "old_status.json"
                status_file.write_text(json.dumps(unavailable), encoding="utf-8")
                cli_env = dict(env, NO_PROXY="127.0.0.1,localhost", no_proxy="127.0.0.1,localhost")
                cli = subprocess.run([sys.executable, str(SERVER / "jetson_edge_client.py"), "live-status",
                                      "--server-url", url, "--status-file", str(status_file), "--once"],
                                     capture_output=True, text=True, timeout=10, env=cli_env)
                observations = {
                    "confirmed_status": good["status"], "provided_breathing_rate": good["breathingRate"],
                    "provided_breathing_estimated_flag": good["breathingEstimated"],
                    "model_unavailable_forwarded_as": missing_payload["status"],
                    "missing_breathing_omitted_by_bridge": "breathingRate" not in missing_payload,
                    "missing_breathing_server_value": missing["breathingRate"],
                    "missing_breathing_server_estimated_flag": missing["breathingEstimated"],
                    "stale_unix_time_1_accepted": cli.returncode == 0 and "[sent]" in cli.stdout,
                }
                checks = good["status"] == "danger" and good["breathingRate"] == 18.2 and not good["breathingEstimated"]
                report = {"scope": "Synthetic loopback HTTP only; no actual CSI, trained model, Flutter device or FCM.",
                          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                            for p in (SERVER / "dev_mock_server.js", SERVER / "jetson_edge_client.py", Path(__file__))},
                          "node_version": subprocess.check_output([args.node, "--version"], text=True).strip(),
                          "temporary_copy_change": "listen address only: 0.0.0.0 -> 127.0.0.1",
                          "confirmed_forwarding_check": checks,
                          "observations": observations,
                          "interpretation": "Missing/unknown/stale observations document unresolved behavior, not release acceptance."}
                (args.output / "server_bridge.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                print(json.dumps(observations))
                return 0 if checks else 1
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())

"""Regression checks for jetson_edge_client.py (stdlib only).

    python -m unittest discover -s app/server/tests -v
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

CLIENT_PATH = Path(__file__).resolve().parents[1] / "jetson_edge_client.py"
_spec = importlib.util.spec_from_file_location("jetson_edge_client_under_test", CLIENT_PATH)
client = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = client
_spec.loader.exec_module(client)


def live_record(fall_state: str | None, **extra) -> dict:
    record = {"schema": "hanium.ruview.live-status.v2", "unix_time": time.time(), "activity": "walking"}
    if fall_state is not None:
        record["fall"] = {"state": fall_state, "alarm": fall_state == "confirmed"}
    record.update(extra)
    return record


class LiveStatusMappingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.args = client.build_parser().parse_args(["live-status", "--once"])

    def test_unavailable_or_unrecognized_states_are_unknown(self) -> None:
        for state in ("model_unavailable", "unknown", "something_new", None):
            payload = client.payload_from_live_status(live_record(state), self.args)
            self.assertEqual(payload["status"], "unknown", state)

    def test_known_states(self) -> None:
        self.assertEqual(client.payload_from_live_status(live_record("confirmed"), self.args)["status"], "danger")
        for state in ("normal", "fall_candidate", "post_fall_check", "recovered"):
            self.assertEqual(client.payload_from_live_status(live_record(state), self.args)["status"], "normal")

    def test_missing_breathing_is_omitted(self) -> None:
        payload = client.payload_from_live_status(live_record("normal", health={"respiratory": {}}), self.args)
        self.assertNotIn("breathingRate", payload)
        ai_payload = client.payload_from_ai_record({"label": "fall"}, self.args)
        self.assertEqual(ai_payload["status"], "danger")
        self.assertNotIn("breathingRate", ai_payload)
        self.assertEqual(client.payload_from_ai_record({"label": "weird"}, self.args)["status"], "unknown")


class StaleRecordTest(unittest.TestCase):
    def test_age_limit(self) -> None:
        now = 1_000_000.0
        self.assertTrue(client.is_stale_live_status({"unix_time": now - 60}, 10, now))
        self.assertFalse(client.is_stale_live_status({"unix_time": now - 1}, 10, now))
        self.assertTrue(client.is_stale_live_status({}, 10, now))
        self.assertFalse(client.is_stale_live_status({"unix_time": now - 60}, 0, now))

    def test_cli_rejects_old_record(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status_file = Path(directory) / "latest_status.json"
            status_file.write_text(json.dumps(live_record("normal", unix_time=1)), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(CLIENT_PATH), "live-status", "--status-file", str(status_file), "--once", "--dry-run"],
                capture_output=True,
                text=True,
                timeout=20,
            )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("[stale]", result.stderr)
        self.assertIn('"status": "unknown"', result.stdout)
        self.assertNotIn("[sent]", result.stdout)


class SourceAndTokenTest(unittest.TestCase):
    def test_default_sources(self) -> None:
        parser = client.build_parser()
        self.assertEqual(parser.parse_args(["once"]).source, "scripted_demo")
        self.assertEqual(parser.parse_args(["sequence"]).source, "scripted_demo")
        self.assertEqual(parser.parse_args(["heartbeat"]).source, "scripted_demo")
        self.assertEqual(parser.parse_args(["live-status"]).source, "jetson_orin")
        self.assertEqual(parser.parse_args(["stdin-json"]).source, "jetson_orin")

    def test_bearer_header_only_when_token_set(self) -> None:
        self.assertNotIn("Authorization", client.json_headers(""))
        self.assertEqual(client.json_headers("abc")["Authorization"], "Bearer abc")


if __name__ == "__main__":
    unittest.main()

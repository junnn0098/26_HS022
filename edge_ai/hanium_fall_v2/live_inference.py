"""Receive LLTF64 CSI and run fall plus conservative health monitoring.

Heart-rate estimation is intentionally excluded. Respiratory rate and apnea
suspicion are CSI-only research outputs. A CSI burst is counted as a cough
candidate first; it becomes a confirmed cough only when an optional trained
cough/confounder checkpoint accepts it.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import time
from collections import Counter, defaultdict, deque
from pathlib import Path

import numpy as np

from .adr018 import LTF_SELECTION_POLICY, extract_lltf_iq, parse_adr018
from .config import FeatureConfig, HealthConfig, RuntimeConfig, load_json
from .cough import CoughCandidate, CoughCandidateDetector
from .fall_state import FallStateMachine
from .features import assemble_multinode_window
from .labels import display_activity as collapse_activity
from .respiratory import RespiratoryMonitor, estimate_node_respiration


def parse_nodes(value: str) -> tuple[int, ...]:
    nodes = tuple(sorted({int(item.strip()) for item in value.split(",")}))
    if not nodes:
        raise argparse.ArgumentTypeError("at least one node is required")
    return nodes


def atomic_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def feature_config_from_checkpoint(checkpoint: dict) -> FeatureConfig:
    raw = checkpoint["feature_config"]
    return FeatureConfig(
        subcarriers=int(raw["subcarriers"]),
        sample_rate_hz=int(raw["sample_rate_hz"]),
        window_seconds=float(raw["window_seconds"]),
        max_nodes=int(raw["max_nodes"]),
        min_node_quality=float(raw.get("min_node_quality", 0.25)),
    )


def collect_window(
    buffers: dict[int, deque],
    expected_nodes: tuple[int, ...],
    start_ns: int,
    config: FeatureConfig,
):
    end_ns = start_ns + int(config.window_seconds * 1e9)
    timestamps: list[int] = []
    nodes: list[int] = []
    iq_frames: list[np.ndarray] = []
    rssi_values: list[int] = []
    for node in expected_nodes:
        for timestamp, iq_value, rssi in buffers[node]:
            if start_ns - 100_000_000 <= timestamp <= end_ns + 100_000_000:
                timestamps.append(timestamp)
                nodes.append(node)
                iq_frames.append(iq_value)
                rssi_values.append(rssi)
    if not iq_frames:
        return None
    return assemble_multinode_window(
        np.asarray(timestamps, dtype=np.int64),
        np.asarray(nodes, dtype=np.uint8),
        np.stack(iq_frames).astype(np.int8, copy=False),
        np.asarray(rssi_values, dtype=np.int8),
        expected_nodes,
        start_ns,
        config,
    )


def unavailable_fall_status() -> dict:
    return {
        "state": "model_unavailable",
        "previous_state": "model_unavailable",
        "changed": False,
        "alarm": False,
        "reason": "fall_checkpoint_not_installed",
        "candidate_hits": 0,
        "lying_hits": 0,
        "recovery_hits": 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Live Hanium RuView fall and respiratory monitoring")
    parser.add_argument("--checkpoint", type=Path, help="optional trained fall/activity checkpoint")
    parser.add_argument("--cough-checkpoint", type=Path, help="optional trained cough/confounder checkpoint")
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5005)
    parser.add_argument("--nodes", type=parse_nodes, default=(1,))
    parser.add_argument("--allow-source")
    parser.add_argument("--device", default="auto")
    parser.add_argument("--runtime-config", type=Path)
    parser.add_argument("--duration", type=float, default=0.0, help="0 means run forever")
    parser.add_argument("--status-file", type=Path, default=Path("runtime/latest_status.json"))
    parser.add_argument("--event-log", type=Path, default=Path("runtime/events.jsonl"))
    args = parser.parse_args()

    config_payload = load_json(args.runtime_config) if args.runtime_config else {}
    runtime_config = RuntimeConfig(**config_payload.get("runtime", {}))
    health_config = HealthConfig(**config_payload.get("health", {}))
    default_feature_config = FeatureConfig(**config_payload.get("feature", {}))

    torch = None
    device = "not_loaded"
    fall_model = None
    activity_labels: list[str] = []
    count_labels: list[str] = []
    feature_config = default_feature_config
    if args.checkpoint:
        if not args.checkpoint.is_file():
            parser.error(f"fall checkpoint not found: {args.checkpoint}")
        import torch as torch_module
        from .fall_checkpoint import require_live_ready_fall_checkpoint
        from .model import model_from_checkpoint

        torch = torch_module
        device = torch.device(
            "cuda" if args.device == "auto" and torch.cuda.is_available() else
            "cpu" if args.device == "auto" else args.device
        )
        checkpoint = torch.load(args.checkpoint, map_location=device, weights_only=False)
        try:
            require_live_ready_fall_checkpoint(checkpoint, torch)
        except ValueError as exc:
            parser.error(f"fall checkpoint rejected: {exc}")
        feature_config = feature_config_from_checkpoint(checkpoint)
        fall_model = model_from_checkpoint(checkpoint, device)
        activity_labels = list(checkpoint["activity_labels"])
        count_labels = list(checkpoint["count_labels"])

    if feature_config.subcarriers != 64:
        parser.error(f"live LLTF contract requires 64 subcarriers, got {feature_config.subcarriers}")
    if len(args.nodes) > feature_config.max_nodes:
        parser.error(f"nodes={len(args.nodes)} exceeds max_nodes={feature_config.max_nodes}")

    cough_model = None
    cough_feature_config = FeatureConfig(window_seconds=2.0)
    cough_labels: list[str] = []
    if args.cough_checkpoint:
        if not args.cough_checkpoint.is_file():
            parser.error(f"cough checkpoint not found: {args.cough_checkpoint}")
        if torch is None:
            import torch as torch_module
            torch = torch_module
            device = torch.device(
                "cuda" if args.device == "auto" and torch.cuda.is_available() else
                "cpu" if args.device == "auto" else args.device
            )
        from .health_model import cough_model_from_checkpoint

        cough_checkpoint = torch.load(args.cough_checkpoint, map_location=device, weights_only=False)
        cough_feature_config = feature_config_from_checkpoint(cough_checkpoint)
        if cough_feature_config.subcarriers != 64:
            parser.error("cough checkpoint is not LLTF64 compatible")
        cough_model = cough_model_from_checkpoint(cough_checkpoint, device)
        cough_labels = list(cough_checkpoint["labels"])

    state_machine = FallStateMachine(runtime_config)
    respiratory_monitor = RespiratoryMonitor(health_config)
    cough_detector = CoughCandidateDetector(health_config)
    pending_coughs: deque[CoughCandidate] = deque()

    stop_requested = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    retained_seconds = max(
        health_config.respiratory_window_seconds + 2.0,
        feature_config.window_seconds + 2.0,
        cough_feature_config.window_seconds + 2.0,
    )
    max_frames = max(1000, int(retained_seconds * 80))
    buffers: defaultdict[int, deque] = defaultdict(lambda: deque(maxlen=max_frames))
    invalid_reasons: Counter[str] = Counter()
    raw_subcarrier_counts: Counter[int] = Counter()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind((args.bind, args.port))
    sock.settimeout(0.05)
    started = time.monotonic()
    next_fall_inference = started + feature_config.window_seconds if fall_model else float("inf")
    next_health_update = started + 2.0
    deadline = started + args.duration if args.duration > 0 else float("inf")
    args.event_log.parent.mkdir(parents=True, exist_ok=True)
    event_output = args.event_log.open("a", encoding="utf-8", buffering=1)

    activity = "unavailable"
    raw_activity = None
    activity_confidence = None
    activity_probabilities: dict[str, float] = {}
    people_count: str | None = None
    people_count_confidence = None
    quality = 0.0
    node_quality = [0.0] * feature_config.max_nodes
    node_mask = [False] * feature_config.max_nodes
    fall_status = unavailable_fall_status()
    respiratory_status = respiratory_monitor.update(started, [], activity, people_count)
    last_apnea_state = respiratory_status["apnea"]["state"]

    def write_event(event_type: str, payload: dict) -> None:
        record = {
            "schema": "hanium.ruview.health-event.v1",
            "unix_time": time.time(),
            "event_type": event_type,
            **payload,
        }
        event_output.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")

    print(
        f"LIVE_HEALTH_READY bind={args.bind}:{args.port} nodes={args.nodes} "
        f"fall_model={'loaded' if fall_model else 'not_installed'} "
        f"cough_model={'loaded' if cough_model else 'not_installed'} device={device}",
        flush=True,
    )

    try:
        while not stop_requested and time.monotonic() < deadline:
            candidate = None
            try:
                data, sender = sock.recvfrom(65535)
            except socket.timeout:
                pass
            else:
                if args.allow_source and sender[0] != args.allow_source:
                    invalid_reasons["source_not_allowed"] += 1
                    continue
                try:
                    frame = parse_adr018(data)
                except ValueError as exc:
                    invalid_reasons[str(exc).split(":", 1)[0]] += 1
                    continue
                if frame.node_id not in args.nodes:
                    continue
                try:
                    canonical_iq = extract_lltf_iq(frame, 64)
                except ValueError as exc:
                    invalid_reasons[str(exc).split(":", 1)[0]] += 1
                    continue
                received_ns = time.monotonic_ns()
                received_seconds = received_ns / 1e9
                raw_subcarrier_counts[frame.subcarriers] += 1
                buffers[frame.node_id].append((received_ns, canonical_iq, frame.rssi_dbm))
                candidate = cough_detector.add_frame(frame.node_id, received_seconds, canonical_iq)
                if candidate is not None:
                    pending_coughs.append(candidate)
                    write_event("cough_like_candidate", {"cough": candidate.to_dict()})

            now = time.monotonic()
            end_ns = time.monotonic_ns()
            oldest_ns = end_ns - int(retained_seconds * 1e9)
            for node in args.nodes:
                while buffers[node] and buffers[node][0][0] < oldest_ns:
                    buffers[node].popleft()

            cough_status_changed = candidate is not None
            while pending_coughs and now >= pending_coughs[0].monotonic_seconds + cough_feature_config.window_seconds / 2.0:
                pending = pending_coughs.popleft()
                if cough_model is None:
                    continue
                start_ns = int((pending.monotonic_seconds - cough_feature_config.window_seconds / 2.0) * 1e9)
                cough_window = collect_window(buffers, args.nodes, start_ns, cough_feature_config)
                if cough_window is None or not np.any(cough_window.node_mask):
                    write_event("cough_classification_skipped", {"reason": "insufficient_signal", "cough": pending.to_dict()})
                    continue
                with torch.no_grad():
                    logits = cough_model(
                        torch.from_numpy(cough_window.features).unsqueeze(0).to(device),
                        torch.from_numpy(cough_window.node_mask).unsqueeze(0).to(device),
                        torch.from_numpy(cough_window.node_quality).unsqueeze(0).to(device),
                    )
                    probabilities = torch.softmax(logits, dim=1)[0].cpu().numpy()
                label_index = int(np.argmax(probabilities))
                label = cough_labels[label_index]
                probability = float(probabilities[label_index])
                confirmed = cough_detector.confirm(pending, probability, label)
                write_event(
                    "cough_confirmed" if confirmed else "cough_candidate_rejected",
                    {
                        "cough": pending.to_dict(),
                        "classification": label,
                        "probability": probability,
                    },
                )
                cough_status_changed = True

            fall_ran = False
            fall_changed = False
            if fall_model is not None and now >= next_fall_inference:
                fall_ran = True
                next_fall_inference = now + runtime_config.inference_interval_seconds
                start_ns = end_ns - int(feature_config.window_seconds * 1e9)
                window = collect_window(buffers, args.nodes, start_ns, feature_config)
                if window is not None and np.any(window.node_mask):
                    with torch.no_grad():
                        outputs = fall_model(
                            torch.from_numpy(window.features).unsqueeze(0).to(device),
                            torch.from_numpy(window.node_mask).unsqueeze(0).to(device),
                            torch.from_numpy(window.node_quality).unsqueeze(0).to(device),
                        )
                        activity_probability = torch.softmax(outputs["activity_logits"], dim=1)[0].cpu().numpy()
                        count_probability = torch.softmax(outputs["count_logits"], dim=1)[0].cpu().numpy()
                        predicted_quality = float(outputs["quality"][0].cpu())
                    activity_index = int(np.argmax(activity_probability))
                    count_index = int(np.argmax(count_probability))
                    activity_probabilities = {
                        label: float(activity_probability[index])
                        for index, label in enumerate(activity_labels)
                    }
                    active_quality = window.node_quality[window.node_mask]
                    quality = min(predicted_quality, float(np.mean(active_quality)))
                    decision = state_machine.update(now, activity_probabilities, quality, count_labels[count_index])
                    activity_confidence = float(activity_probability[activity_index])
                    raw_activity = activity_labels[activity_index]
                    activity = (
                        collapse_activity(raw_activity)
                        if activity_confidence >= runtime_config.min_activity_confidence
                        and quality >= runtime_config.min_quality
                        else "unknown"
                    )
                    if decision.alarm:
                        activity = "fall"
                    people_count = count_labels[count_index]
                    people_count_confidence = float(count_probability[count_index])
                    node_quality = window.node_quality.tolist()
                    node_mask = window.node_mask.tolist()
                    fall_status = decision.to_dict()
                    fall_changed = decision.changed or decision.alarm
                else:
                    activity = "unknown"
                    quality = 0.0

            health_due = health_config.enabled and now >= next_health_update
            apnea_changed = False
            if health_due:
                next_health_update = now + 2.0
                estimates = []
                for node in args.nodes:
                    if len(buffers[node]) < 8:
                        continue
                    timestamps = np.asarray([item[0] for item in buffers[node]], dtype=np.int64)
                    iq_values = np.stack([item[1] for item in buffers[node]]).astype(np.int8, copy=False)
                    try:
                        estimate = estimate_node_respiration(node, timestamps, iq_values, end_ns, health_config)
                    except ValueError as exc:
                        invalid_reasons[f"respiratory_{str(exc).split(':', 1)[0]}"] += 1
                        continue
                    if estimate is not None:
                        estimates.append(estimate)
                respiratory_status = respiratory_monitor.update(now, estimates, activity, people_count)
                apnea_state = respiratory_status["apnea"]["state"]
                apnea_changed = apnea_state != last_apnea_state
                if apnea_changed and apnea_state in {"candidate", "suspected"}:
                    write_event("apnea_suspicion", {"respiratory": respiratory_status})
                last_apnea_state = apnea_state

            if not (health_due or fall_ran or cough_status_changed or apnea_changed):
                continue
            status = {
                "schema": "hanium.ruview.live-status.v2",
                "unix_time": time.time(),
                "activity": activity,
                "raw_activity": raw_activity,
                "activity_confidence": activity_confidence,
                "activity_probabilities": activity_probabilities,
                "people_count": people_count if people_count is not None else "unavailable",
                "people_count_confidence": people_count_confidence,
                "quality": quality,
                "node_quality": node_quality,
                "node_mask": node_mask,
                "fall_model_available": fall_model is not None,
                "fall": fall_status,
                "health": {
                    "respiratory": respiratory_status,
                    "cough": cough_detector.status(cough_model is not None),
                },
                "invalid_reasons": dict(invalid_reasons),
                "raw_subcarrier_counts": dict(raw_subcarrier_counts),
                "canonical_subcarriers": 64,
                "selected_ltf": "LLTF",
                "ltf_selection_policy": LTF_SELECTION_POLICY,
            }
            atomic_json(args.status_file, status)
            if fall_changed:
                write_event("fall_state", {"status": status})
            print("LIVE_STATUS=" + json.dumps(status, ensure_ascii=False, separators=(",", ":")), flush=True)
    finally:
        sock.close()
        event_output.close()
    print("RESULT=LIVE_HEALTH_STOPPED_CLEANLY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

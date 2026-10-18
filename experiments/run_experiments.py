"""Run reproducible software experiments; never claims real-world model accuracy."""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.metadata
import io
import json
import platform
import subprocess
import sys
import unittest
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "edge_ai"))
from hanium_fall_v2.config import FeatureConfig, HealthConfig, RuntimeConfig
from hanium_fall_v2.fall_state import FallStateMachine
from hanium_fall_v2.features import assemble_multinode_window, build_node_features
from hanium_fall_v2.respiratory import estimate_node_respiration

SEEDS = (7, 19, 42)
BPM_VALUES = (8.0, 12.3, 15.0, 20.7, 27.4)
plt.rcParams.update({"svg.fonttype": "none", "svg.hashsalt": "hanium-experiments",
                     "font.size": 10, "axes.spines.top": False,
                     "axes.spines.right": False, "axes.titleweight": "bold"})


def lf_sha256(path: Path) -> str:
    """SHA-256 of the content with CRLF normalised to LF, so Windows and Linux checkouts agree."""
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def save_figure(fig, path: Path) -> None:
    fig.savefig(path, bbox_inches="tight", metadata={"Date": None})
    # Matplotlib's SVG paths contain line-end spaces; normalize for readable diffs.
    path.write_text("\n".join(line.rstrip() for line in path.read_text(encoding="utf-8").splitlines()) + "\n", encoding="utf-8")
    plt.close(fig)


def fall_experiment(output: Path) -> dict:
    fixtures = json.loads((ROOT / "experiments/fall_scenarios.json").read_text())
    rows, outcomes = [], []
    for scenario in fixtures["scenarios"]:
        machine = FallStateMachine(RuntimeConfig())
        own = []
        for segment in scenario["segments"]:
            for _ in range(segment["steps"]):
                now = len(own) * fixtures["interval_seconds"]
                probabilities = {segment["activity"]: 0.90}
                probabilities["other_motion"] = probabilities.get("other_motion", 0.0) + 0.10
                quality, people = segment.get("quality", 0.95), segment.get("people", "1")
                result = machine.update(now, probabilities, quality, people)
                own.append({"scenario": scenario["id"], "time_s": now,
                            "input_activity": segment["activity"], "quality": quality,
                            "people": people, **result.to_dict()})
        alarm_times = [r["time_s"] for r in own if r["alarm"]]
        recovery_times = [r["time_s"] for r in own if r["state"] == "recovered"]
        final = own[-1]["state"]
        outcomes.append({"scenario": scenario["id"], "final_state": final,
                         "any_alarm": bool(alarm_times),
                         "first_alarm_s": min(alarm_times) if alarm_times else None,
                         "first_recovery_s": min(recovery_times) if recovery_times else None,
                         "expected_final": scenario["expected_final"],
                         "expected_alarm": scenario["expected_alarm"],
                         "matches_expected": final == scenario["expected_final"] and bool(alarm_times) == scenario["expected_alarm"]})
        rows.extend(own)
    write_csv(output / "fall_trace.csv", rows)
    write_json(output / "fall_summary.json", outcomes)
    states = {s: i for i, s in enumerate(["normal", "fall_candidate", "post_fall_check", "confirmed", "recovered", "unknown"])}
    selected = ["single_spike", "fall_then_lying", "intermittent_lying", "hold_then_recover"]
    fig, axes = plt.subplots(4, 1, figsize=(10, 10), constrained_layout=True)
    for ax, name in zip(axes, selected):
        points = [r for r in rows if r["scenario"] == name]
        ax.step([r["time_s"] for r in points], [states[r["state"]] for r in points], where="post", color="#14847d", linewidth=2.2)
        ax.set_yticks(list(states.values()), list(states))
        ax.set_ylim(-0.3, 5.3)
        ax.set_title(name.replace("_", " "), loc="left")
        ax.set_xlabel("Seconds since first injected probability (not end-to-end latency)")
        ax.grid(alpha=0.18)
    fig.suptitle("Synthetic probability sequences / post-processing behavior", fontsize=14)
    save_figure(fig, output / "fall_timeline.svg")
    return {"scenarios": len(outcomes), "matched": sum(x["matches_expected"] for x in outcomes), "outcomes": outcomes}


def synthetic_iq(bpm: float, noise: float, seed: int, seconds: float = 61.0):
    rng = np.random.default_rng(seed)
    t = np.arange(int(seconds * 32), dtype=np.float64) / 32
    phase = 0.02 * np.arange(64)[None, :]
    wave = np.sin(2 * np.pi * bpm / 60 * t[:, None] + phase)
    real = 35 + 7 * wave + rng.normal(0, noise, wave.shape)
    imag = 8 + 2 * wave + rng.normal(0, noise, wave.shape)
    iq = np.clip(np.rint(np.stack([real, imag], axis=-1)), -128, 127).astype(np.int8)[:, None]
    iq[:, :, :2] = 0
    return (t * 1e9).astype(np.int64), iq


def respiration_experiment(output: Path) -> dict:
    config = HealthConfig()
    rows = []
    for bpm in BPM_VALUES:
        for noise in (0.0, 0.7, 3.0, 8.0):
            for seed in SEEDS:
                times, iq = synthetic_iq(bpm, noise, seed)
                est = estimate_node_respiration(1, times, iq, int(times[-1]), config)
                rows.append({"target_bpm": bpm, "noise_std_iq_units": noise, "seed": seed,
                             "estimated_bpm": est.bpm if est else None,
                             "absolute_error_bpm": abs(est.bpm - bpm) if est else None,
                             "confidence": est.confidence if est else None,
                             "motion_score": est.motion_score if est else None,
                             "estimate_returned": est is not None})
    write_csv(output / "respiration_trials.csv", rows)
    # These probes include cases with no physiological periodic signal. A returned
    # frequency in noise is evidence to inspect, not a successful respiration trial.
    probes = []
    times, base = synthetic_iq(15, 0.7, 7)
    for name in ("zero_signal", "constant_signal", "white_noise_only", "short_history", "stale_signal"):
        t, iq, end = times.copy(), base.copy(), int(times[-1])
        if name == "zero_signal":
            iq[:] = 0
        elif name == "constant_signal":
            iq[:] = 20
            iq[:, :, :2] = 0
        elif name == "white_noise_only":
            iq = np.clip(np.rint(np.random.default_rng(7).normal(20, 5, iq.shape)), -128, 127).astype(np.int8)
            iq[:, :, :2] = 0
        elif name == "short_history":
            t, iq = t[:640], iq[:640]
            end = int(t[-1])
        else:
            end += 3_000_000_000
        est = estimate_node_respiration(1, t, iq, end, config)
        probes.append({"case": name, "estimate_returned": est is not None,
                       "bpm": est.bpm if est else None,
                       "confidence": est.confidence if est else None,
                       "motion_score": est.motion_score if est else None})
    write_json(output / "respiration_probes.json", probes)
    summaries = []
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.4), constrained_layout=True)
    for noise in (0.0, 0.7, 3.0, 8.0):
        selected = [r for r in rows if r["noise_std_iq_units"] == noise]
        valid = [r for r in selected if r["estimate_returned"]]
        errors = [r["absolute_error_bpm"] for r in valid]
        summaries.append({"noise_std_iq_units": noise, "trials": len(selected), "returned": len(valid),
                          "mae_bpm": float(np.mean(errors)) if errors else None,
                          "max_error_bpm": max(errors) if errors else None})
        x, y = [], []
        for bpm in BPM_VALUES:
            values = [r["absolute_error_bpm"] for r in valid if r["target_bpm"] == bpm]
            if values:
                x.append(bpm)
                y.append(np.mean(values))
        axes[0].plot(x, y, marker="o", label=f"noise SD {noise:g}")
    axes[0].set(xlabel="Injected frequency (cycles/min)", ylabel="Mean absolute frequency error", title="3 seeds per condition; synthetic signal")
    axes[0].legend(fontsize=8)
    axes[0].grid(alpha=0.2)
    axes[1].bar([str(x["noise_std_iq_units"]) for x in summaries], [x["returned"] for x in summaries], color="#14847d")
    axes[1].set(xlabel="Noise SD in signed IQ units (not SNR/dB)", ylabel="Returned estimates / 15 trials", ylim=(0, 17), title="Estimator coverage; not clinical accuracy")
    save_figure(fig, output / "respiration_sweep.svg")
    write_json(output / "respiration_summary.json", summaries)
    return {"trials": len(rows), "summaries": summaries, "probes": probes}


def loss_experiment(output: Path) -> dict:
    config = FeatureConfig()
    # 165 source packets at approximately 33 pps; first and last retained in both patterns.
    times = (np.arange(165) * 1e9 / 33).astype(np.int64)
    _, iq = synthetic_iq(15, 0.7, 7, seconds=165 / 32)
    rssi = np.full(len(times), -60, dtype=np.int8)
    rows = []
    for fraction in (0, 0.1, 0.25, 0.5, 0.75, 0.9):
        removed = int(round(len(times) * fraction))
        for seed in SEEDS:
            for pattern in ("random", "middle_burst"):
                if pattern == "random":
                    dropped = np.random.default_rng(seed).choice(np.arange(1, len(times) - 1), removed, replace=False)
                else:
                    start = (len(times) - removed) // 2
                    dropped = np.arange(start, start + removed)
                keep = np.ones(len(times), dtype=bool)
                keep[dropped] = False
                features, quality = build_node_features(times[keep], iq[keep], rssi[keep], 0, config)
                rows.append({"drop_fraction_requested": fraction, "drop_fraction_actual": removed / len(times),
                             "pattern": pattern, "seed": seed, "packets_retained": int(keep.sum()),
                             "max_gap_s": float(np.diff(times[keep]).max() / 1e9), "quality": quality,
                             "node_mask_eligible": quality >= config.min_node_quality,
                             "finite_features": bool(np.isfinite(features).all())})
    write_csv(output / "packet_loss_trials.csv", rows)
    masks = []
    for present in (0, 1, 2, 4):
        batch_times = np.tile(times, present)
        batch_iq = np.tile(iq, (present, 1, 1, 1))
        batch_ids = np.repeat(np.arange(1, present + 1), len(times))
        window = assemble_multinode_window(batch_times, batch_ids, batch_iq,
                                            np.tile(rssi, present), [1, 2, 3, 4], 0, config)
        masks.append({"nodes_present": present, "shape": list(window.features.shape),
                      "mask": window.node_mask.tolist(), "quality": window.node_quality.tolist(),
                      "finite_features": bool(np.isfinite(window.features).all())})
    write_json(output / "node_mask_results.json", masks)
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.3), constrained_layout=True)
    for pattern, marker, color in (("random", "o", "#14847d"), ("middle_burst", "s", "#bc7040")):
        selected = [r for r in rows if r["seed"] == 7 and r["pattern"] == pattern]
        x = [r["drop_fraction_actual"] * 100 for r in selected]
        axes[0].plot(x, [r["quality"] for r in selected], marker=marker, color=color, label=pattern)
        axes[1].plot(x, [r["max_gap_s"] for r in selected], marker=marker, color=color, label=pattern)
    axes[0].axhline(config.min_node_quality, color="#777", linestyle="--", label="node mask threshold")
    for ax in axes:
        ax.set_xlabel("Removed packets (%) / endpoints retained")
        ax.grid(alpha=0.2)
        ax.legend(fontsize=8)
    axes[0].set(ylabel="Feature quality", title="Same packet count yields same quality")
    axes[1].set(ylabel="Maximum inter-packet gap (seconds)", title="Internal gaps differ / seed 7")
    save_figure(fig, output / "packet_loss.svg")
    return {"trials": len(rows), "all_finite": all(r["finite_features"] for r in rows), "node_masks": masks}


def existing_checks(output: Path) -> dict:
    log = io.StringIO()
    suite = unittest.defaultTestLoader.discover(str(ROOT / "edge_ai/tests"))
    result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
    (output / "unit_tests.txt").write_text(log.getvalue(), encoding="utf-8")
    selftest = subprocess.run([sys.executable, "-m", "hanium_fall_v2.selftest"],
                              cwd=ROOT / "edge_ai", capture_output=True, text=True, timeout=60)
    (output / "selftest.txt").write_text(selftest.stdout + selftest.stderr, encoding="utf-8")
    summary = {"discovered": result.testsRun,
               "passed": result.testsRun - len(result.skipped) - len(result.failures) - len(result.errors),
               "skipped": [{"test": str(test), "reason": reason} for test, reason in result.skipped],
               "failures": len(result.failures), "errors": len(result.errors),
               "successful": result.wasSuccessful(), "selftest_exit_code": selftest.returncode}
    write_json(output / "test_summary.json", summary)
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "experiments/results/local")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    modules = ["config.py", "fall_state.py", "features.py", "respiratory.py"]
    inputs = [ROOT / "edge_ai/hanium_fall_v2" / m for m in modules] + [Path(__file__), ROOT / "experiments/fall_scenarios.json"]
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True)
    metadata = {"executed_at_utc": datetime.now(timezone.utc).isoformat(),
                "checkout_commit": revision.stdout.strip() if revision.returncode == 0 else "unavailable",
                "python": platform.python_version(), "platform": platform.system(), "machine": platform.machine(),
                "dependencies": {x: importlib.metadata.version(x) for x in ("numpy", "matplotlib")},
                "configs": {"feature": asdict(FeatureConfig()), "runtime": asdict(RuntimeConfig()), "health": asdict(HealthConfig())},
                "seeds": list(SEEDS),
                "hash_method": "SHA-256 of file content with CRLF normalised to LF; POSIX paths from the repository root",
                "input_sha256": {p.relative_to(ROOT).as_posix(): lf_sha256(p) for p in inputs},
                "scope": "Synthetic software experiments only. No trained weights, human measurements, ESP32, Jetson, Flutter or FCM."}
    write_json(output / "environment.json", metadata)
    summary = {"fall": fall_experiment(output), "respiration": respiration_experiment(output),
               "packet_loss": loss_experiment(output),
               "existing_checks": existing_checks(output)}
    write_json(output / "summary.json", summary)
    print(json.dumps({"output": str(output), "fall_scenarios": summary["fall"]["scenarios"],
                      "fall_matched": summary["fall"]["matched"], "respiration_trials": summary["respiration"]["trials"],
                      "loss_trials": summary["packet_loss"]["trials"]}))
    passed = (summary["fall"]["matched"] == summary["fall"]["scenarios"]
              and summary["packet_loss"]["all_finite"]
              and summary["existing_checks"]["successful"]
              and summary["existing_checks"]["selftest_exit_code"] == 0)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

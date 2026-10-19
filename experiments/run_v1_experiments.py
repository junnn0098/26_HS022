"""Reproduce every v1 (134ch x 500 1D-CNN) result published in experiments/results/v1.

Needs the dataset NPZ files in dataset/data (python dataset/tools/download.py) and
PyTorch. Runs on CPU in about 15 minutes with the default 3 parallel jobs.

  python experiments/run_v1_experiments.py            # all runs
  python experiments/run_v1_experiments.py --only temporal_lltf
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EDGE = ROOT / "edge_ai"
OUT = ROOT / "experiments" / "results" / "v1"
WEIGHTS = EDGE / "hanium_fall_v1" / "weights"

# name: (protocol, channels, seeds[, batches])
TRAINING_RUNS = {
    "report_1019_random_all": ("random", "all", [0, 1, 2, 3, 4], ["b1_0708_0709"]),
    "report_1019_recording_all": ("recording", "all", [0], ["b1_0708_0709"]),
    "random_all": ("random", "all", [0, 1, 2, 3, 4]),
    "random_non_csi": ("random", "non_csi", [0, 1, 2, 3, 4]),
    "recording_all": ("recording", "all", [0]),
    "recording_lltf": ("recording", "lltf", [0]),
    "temporal_all": ("temporal", "all", [0, 1, 2]),
    "temporal_csi": ("temporal", "csi", [0, 1, 2]),
    "temporal_lltf": ("temporal", "lltf", [0, 1, 2]),
}
TEAM_WEIGHTS = {"team_v1_0717": "team_v1_0717.pth", "team_v1_0803": "team_v1_0803.pth"}


def run(command: list[str], log: Path) -> int:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8") as handle:
        return subprocess.run(command, cwd=EDGE, stdout=handle, stderr=subprocess.STDOUT).returncode


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--only", nargs="*", help="subset of run names")
    args = parser.parse_args()
    known = set(TRAINING_RUNS) | set(TEAM_WEIGHTS) | {"team_v1_0717_later"}
    unknown = sorted(set(args.only or []) - known)
    if unknown:
        parser.error(f"unknown run names: {', '.join(unknown)} (choose from {', '.join(sorted(known))})")

    jobs = []
    for name, (protocol, channels, seeds, *batches) in TRAINING_RUNS.items():
        if args.only and name not in args.only:
            continue
        extra = ["--batches", *batches[0]] if batches else []
        jobs.append((name, [sys.executable, "-m", "hanium_fall_v1.train", "--protocol", protocol,
                            "--channels", channels, "--seeds", *map(str, seeds), "--threads", str(args.threads),
                            *extra, "--out", str(OUT / name)]))
    for name, weights in TEAM_WEIGHTS.items():
        if args.only and name not in args.only:
            continue
        jobs.append((name, [sys.executable, "-m", "hanium_fall_v1.evaluate", "--weights", str(WEIGHTS / weights),
                            "--channels", "all", "--out", str(OUT / f"{name}.json")]))
    if not args.only or "team_v1_0717_later" in args.only:
        # 07-17 weights on the two later collection days only (made before those days existed)
        jobs.append(("team_v1_0717_later", [sys.executable, "-m", "hanium_fall_v1.evaluate", "--weights",
                                            str(WEIGHTS / TEAM_WEIGHTS["team_v1_0717"]), "--channels", "all",
                                            "--batches", "b3_0724", "b4_0728",
                                            "--out", str(OUT / "team_v1_0717_later.json")]))

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        codes = dict(zip([n for n, _ in jobs], pool.map(lambda job: run(job[1], OUT / "logs" / f"{job[0]}.log"), jobs)))
    for name, code in codes.items():
        print(f"{name}: {'ok' if code == 0 else f'failed ({code})'}")
    if any(codes.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()

"""Train and evaluate the v1 1D-CNN (134ch x 500) on the measured dataset.

Two runs, both with a label-stratified 80/20 window split repeated over 5 seeds:
  b1_random   1st and 2nd collection (b1_0708_0709, 1,019 windows)
  random_all  all collection days (2,217 windows)

Needs the dataset NPZ files in dataset/data (python dataset/tools/download.py) and
PyTorch. Results go to experiments/results/v1/<run>/ and take about 5 minutes on CPU
with the defaults (the published results were made with --threads 2).

  python experiments/run_v1_experiments.py            # both runs
  python experiments/run_v1_experiments.py --only b1_random
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

SEEDS = [0, 1, 2, 3, 4]
# name: dataset batches (None = all)
RUNS = {
    "b1_random": ["b1_0708_0709"],
    "random_all": None,
}


def run(command: list[str], log: Path) -> int:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8") as handle:
        return subprocess.run(command, cwd=EDGE, stdout=handle, stderr=subprocess.STDOUT).returncode


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--only", nargs="*", help="subset of run names")
    args = parser.parse_args()
    unknown = sorted(set(args.only or []) - set(RUNS))
    if unknown:
        parser.error(f"unknown run names: {', '.join(unknown)} (choose from {', '.join(RUNS)})")

    jobs = []
    for name, batches in RUNS.items():
        if args.only and name not in args.only:
            continue
        extra = ["--batches", *batches] if batches else []
        jobs.append((name, [sys.executable, "-m", "hanium_fall_v1.train", "--protocol", "random",
                            "--channels", "all", "--seeds", *map(str, SEEDS), "--threads", str(args.threads),
                            *extra, "--out", str(OUT / name)]))

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        codes = dict(zip([n for n, _ in jobs], pool.map(lambda job: run(job[1], OUT / "logs" / f"{job[0]}.log"), jobs)))
    for name, code in codes.items():
        print(f"{name}: {'ok' if code == 0 else f'failed ({code})'}")
    if any(codes.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()

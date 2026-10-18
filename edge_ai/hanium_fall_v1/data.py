"""Load the measured CSI window dataset (`dataset/`) and prepare model inputs."""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_METADATA = REPO_ROOT / "dataset" / "metadata" / "windows.csv"
DEFAULT_NPZ_DIR = REPO_ROOT / "dataset" / "data"

# Channel layout of the team's 134-wide windows (verified on the dataset):
#   0-4    not CSI. The team's amplitude extractor starts two bytes into the RuView
#          payload, so these hold frequency/sequence-counter/RSSI/noise/flag bytes.
#   5-68   first LLTF block (64 subcarriers; channel 5 is the masked first word).
#   69-132 second 64-value block. Its meaning depends on the packet width the node
#          sent (134-wide sessions vs 198-wide sessions), so it shifts between days.
#   133    0 for 134-wide packets, a third-block value for 198-wide packets.
NON_CSI_CHANNELS = (0, 1, 2, 3, 4)
LLTF_CHANNELS = tuple(range(5, 69))


def read_metadata(path: Path = DEFAULT_METADATA) -> list[dict]:
    with Path(path).open(encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    for row in rows:
        row["npz_index"] = int(row["npz_index"])
        row["is_fall"] = int(row["is_fall"])
    return rows


def load_windows(npz_dir: Path = DEFAULT_NPZ_DIR, metadata: Path = DEFAULT_METADATA,
                 batches: list[str] | None = None) -> tuple[np.ndarray, list[dict]]:
    """Return X with shape (N, 500, 134) and the matching metadata rows."""
    rows = [row for row in read_metadata(metadata) if not batches or row["batch"] in batches]
    arrays, kept = [], []
    for npz_file in dict.fromkeys(row["npz_file"] for row in rows):
        path = Path(npz_dir) / npz_file
        if not path.exists():
            raise FileNotFoundError(f"{path} is missing; run `python dataset/tools/download.py` first")
        with np.load(path) as archive:
            data, ids = archive["X"], archive["window_id"]
        selected = [row for row in rows if row["npz_file"] == npz_file]
        index = np.array([row["npz_index"] for row in selected])
        if not np.array_equal(ids[index], [row["window_id"] for row in selected]):
            raise ValueError(f"{npz_file} does not match {metadata}")
        arrays.append(data[index])
        kept.extend(selected)
    return np.concatenate(arrays).astype(np.float32, copy=False), kept


CHANNEL_SETS = {
    "all": tuple(range(134)),
    "csi": tuple(range(5, 134)),
    "lltf": LLTF_CHANNELS,
    "non_csi": NON_CSI_CHANNELS,
}


def preprocess(windows: np.ndarray, channels: str = "all") -> np.ndarray:
    """(N, 500, 134) -> (N, 134, 500) with the team's per-window z-score.

    The team normalised each window with one mean/std over all 134x500 values
    (`channels="all"`). Other channel sets zero every channel outside the set and
    normalise with the kept ones only: `"csi"` drops the non-CSI bytes, `"lltf"`
    keeps the block that means the same thing on every day, `"non_csi"` keeps only
    the non-CSI bytes (a probe for shortcut learning).
    """
    x = np.asarray(windows, dtype=np.float32)
    single = x.ndim == 2
    if single:
        x = x[None]
    x = np.transpose(x, (0, 2, 1)).copy()
    keep = list(CHANNEL_SETS[channels])
    kept = x[:, keep]
    mean = kept.mean(axis=(1, 2), keepdims=True)
    std = kept.std(axis=(1, 2), keepdims=True)
    out = np.zeros_like(x)
    out[:, keep] = (kept - mean) / (std + 1e-8)
    return out[0] if single else out

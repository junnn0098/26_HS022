"""Strict parser for the RuView ADR-018 CSI UDP wire format."""

from __future__ import annotations

import struct
from dataclasses import dataclass

import numpy as np


MAGIC = 0xC5110001
HEADER = struct.Struct("<IBBHIIbbBB")
HEADER_SIZE = HEADER.size
CANONICAL_SUBCARRIERS = 64
SUPPORTED_RAW_SUBCARRIERS = (64, 128, 192)
LLTF_SUBCARRIERS = 64
LLTF_INVALID_PREFIX_COMPLEX = 2
ADR110_BANDWIDTH_MASK = 0x03
ADR110_BANDWIDTH_20MHZ = 0
SUPPORTED_LLTF_PPDU = (0x00, 0xFF)
LTF_SELECTION_POLICY = "lltf_first_block_mask_first_word_v1"
# Backward-compatible metadata key used by existing capture readers.
NORMALIZATION_POLICY = LTF_SELECTION_POLICY


@dataclass(frozen=True)
class CsiFrame:
    node_id: int
    antennas: int
    subcarriers: int
    frequency_mhz: int
    sequence: int
    rssi_dbm: int
    noise_floor_dbm: int
    ppdu: int
    flags: int
    iq: np.ndarray
    packet_size: int
    trailing_bytes: int

    @property
    def bandwidth_code(self) -> int:
        """Return the ADR-110 bandwidth code stored in flags bits 0..1."""
        return self.flags & ADR110_BANDWIDTH_MASK

    @property
    def ltf_block_count(self) -> int:
        """Return the number of 64-complex-value LTF blocks in the payload."""
        if self.subcarriers not in SUPPORTED_RAW_SUBCARRIERS:
            return 0
        return self.subcarriers // LLTF_SUBCARRIERS

    @property
    def amplitude(self) -> np.ndarray:
        """Return amplitude with shape (antennas, subcarriers)."""
        values = self.iq.astype(np.float32, copy=False)
        return np.hypot(values[..., 0], values[..., 1])

    @property
    def phase(self) -> np.ndarray:
        """Return wrapped phase in radians with shape (antennas, subcarriers)."""
        values = self.iq.astype(np.float32, copy=False)
        return np.arctan2(values[..., 1], values[..., 0])


def parse_adr018(data: bytes) -> CsiFrame:
    """Parse one ADR-018 datagram and retain the original signed I/Q bytes."""
    if len(data) < HEADER_SIZE:
        raise ValueError(f"short packet: {len(data)} < {HEADER_SIZE}")

    (
        magic,
        node_id,
        antennas,
        subcarriers,
        frequency_mhz,
        sequence,
        rssi_dbm,
        noise_floor_dbm,
        ppdu,
        flags,
    ) = HEADER.unpack_from(data)

    if magic != MAGIC:
        raise ValueError(f"different magic: 0x{magic:08X}")
    if not 1 <= node_id <= 255:
        raise ValueError(f"invalid node id: {node_id}")
    if not 1 <= antennas <= 4:
        raise ValueError(f"invalid antenna count: {antennas}")
    if not 1 <= subcarriers <= 2048:
        raise ValueError(f"invalid subcarrier count: {subcarriers}")

    iq_byte_count = antennas * subcarriers * 2
    expected_size = HEADER_SIZE + iq_byte_count
    if len(data) < expected_size:
        raise ValueError(
            f"truncated I/Q: got {len(data)}, expected at least {expected_size}"
        )

    iq = np.frombuffer(
        data,
        dtype=np.int8,
        count=iq_byte_count,
        offset=HEADER_SIZE,
    ).copy()
    iq = iq.reshape(antennas, subcarriers, 2)

    return CsiFrame(
        node_id=node_id,
        antennas=antennas,
        subcarriers=subcarriers,
        frequency_mhz=frequency_mhz,
        sequence=sequence,
        rssi_dbm=rssi_dbm,
        noise_floor_dbm=noise_floor_dbm,
        ppdu=ppdu,
        flags=flags,
        iq=iq,
        packet_size=len(data),
        trailing_bytes=len(data) - expected_size,
    )


def _extract_first_lltf_block(
    iq: np.ndarray,
    *,
    mask_first_word: bool,
) -> np.ndarray:
    """Extract the first 64-value LTF block from an already parsed payload."""
    values = np.asarray(iq)
    if values.ndim != 3 or values.shape[-1] != 2:
        raise ValueError(
            "iq must have shape (antennas, subcarriers, 2), "
            f"got {values.shape}"
        )
    raw_subcarriers = int(values.shape[1])
    if raw_subcarriers not in SUPPORTED_RAW_SUBCARRIERS:
        raise ValueError(
            "unsupported raw subcarrier count: "
            f"{raw_subcarriers}; expected one of {SUPPORTED_RAW_SUBCARRIERS}"
        )
    lltf = values[:, :LLTF_SUBCARRIERS, :].copy()
    if mask_first_word:
        # ESP32-S3 can mark the first four CSI bytes (two complex samples) as
        # invalid. ADR-018 does not carry first_word_invalid, so mask these two
        # positions for every frame instead of allowing intermittent garbage or
        # shifting the remaining subcarrier positions.
        lltf[:, :LLTF_INVALID_PREFIX_COMPLEX, :] = 0
    return lltf


def extract_lltf_iq(
    frame: CsiFrame,
    target_subcarriers: int = CANONICAL_SUBCARRIERS,
    *,
    mask_first_word: bool = True,
    require_20mhz: bool = True,
) -> np.ndarray:
    """Return only the LLTF block accepted by the Jetson model pipeline.

    The deployed ESP32-S3 firmware enables LLTF and ESP-IDF serializes enabled
    blocks in LLTF, HT-LTF, STBC-HT-LTF order. Raw widths 64/128/192 therefore
    contain one/two/three 64-complex-value blocks; only the first block is used.

    ADR-110 flags bits 0..1 are checked so wider-band frames cannot silently
    enter the 20 MHz model. HE PPDU types are also rejected because this S3
    pipeline is defined only for HT/legacy LLTF CSI.
    """
    if target_subcarriers != LLTF_SUBCARRIERS:
        raise ValueError(
            f"LLTF target must be {LLTF_SUBCARRIERS}, got {target_subcarriers}"
        )
    if frame.iq.shape[0] != frame.antennas or frame.iq.shape[1] != frame.subcarriers:
        raise ValueError("frame metadata/IQ shape mismatch")
    if require_20mhz and frame.bandwidth_code != ADR110_BANDWIDTH_20MHZ:
        raise ValueError(f"non-20MHz frame: bandwidth code {frame.bandwidth_code}")
    if frame.ppdu not in SUPPORTED_LLTF_PPDU:
        raise ValueError(f"unsupported PPDU for S3 LLTF: {frame.ppdu}")
    return _extract_first_lltf_block(frame.iq, mask_first_word=mask_first_word)


def normalize_20mhz_iq(
    iq: np.ndarray,
    target_subcarriers: int = CANONICAL_SUBCARRIERS,
) -> np.ndarray:
    """Compatibility wrapper; new code should call :func:`extract_lltf_iq`.

    This wrapper cannot validate ADR-110 bandwidth or PPDU metadata because it
    receives only an I/Q array. It still applies the same LLTF-prefix mask.
    """
    if target_subcarriers != LLTF_SUBCARRIERS:
        raise ValueError(
            f"LLTF target must be {LLTF_SUBCARRIERS}, got {target_subcarriers}"
        )
    return _extract_first_lltf_block(iq, mask_first_word=True)


def sequence_gap(previous: int, current: int) -> int:
    """Return missing packet count, or -1 for duplicate/reordered packets."""
    delta = (current - previous) & 0xFFFFFFFF
    if delta == 0 or delta >= 0x80000000:
        return -1
    return max(0, delta - 1)

import struct
import unittest

import numpy as np

from hanium_fall_v2.adr018 import (
    HEADER,
    MAGIC,
    extract_lltf_iq,
    parse_adr018,
    sequence_gap,
)


class Adr018Tests(unittest.TestCase):
    def make_packet(self) -> bytes:
        header = HEADER.pack(MAGIC, 1, 1, 3, 2437, 42, -61, -96, 7, 3)
        iq = np.asarray([[3, 4], [-5, 12], [0, -7]], dtype=np.int8).tobytes()
        return header + iq

    @staticmethod
    def make_csi_frame(
        raw: np.ndarray,
        *,
        ppdu: int = 0,
        flags: int = 0,
    ):
        header = HEADER.pack(
            MAGIC,
            1,
            int(raw.shape[0]),
            int(raw.shape[1]),
            2437,
            42,
            -61,
            -96,
            ppdu,
            flags,
        )
        return parse_adr018(header + raw.astype(np.int8, copy=False).tobytes())

    def test_parse_and_derived_features(self) -> None:
        frame = parse_adr018(self.make_packet())
        self.assertEqual(frame.node_id, 1)
        self.assertEqual(frame.iq.shape, (1, 3, 2))
        np.testing.assert_allclose(frame.amplitude, [[5.0, 13.0, 7.0]])

    def test_wrong_magic_is_rejected(self) -> None:
        packet = bytearray(self.make_packet())
        struct.pack_into("<I", packet, 0, 0)
        with self.assertRaisesRegex(ValueError, "different magic"):
            parse_adr018(bytes(packet))

    def test_sequence_gap_and_wrap(self) -> None:
        self.assertEqual(sequence_gap(10, 11), 0)
        self.assertEqual(sequence_gap(10, 13), 2)
        self.assertEqual(sequence_gap(0xFFFFFFFF, 0), 0)
        self.assertEqual(sequence_gap(10, 10), -1)

    def test_64_128_192_extract_same_lltf(self) -> None:
        first = np.arange(128, dtype=np.int16).astype(np.int8).reshape(1, 64, 2)
        expected = first.copy()
        expected[:, :2, :] = 0
        for raw_subcarriers in (64, 128, 192):
            blocks = raw_subcarriers // 64
            raw = np.concatenate(
                [first] + [np.full_like(first, block) for block in range(1, blocks)],
                axis=1,
            )
            lltf = extract_lltf_iq(self.make_csi_frame(raw))
            self.assertEqual(lltf.shape, (1, 64, 2))
            np.testing.assert_array_equal(lltf, expected)

    def test_optional_ht_and_stbc_blocks_never_leak_into_lltf(self) -> None:
        lltf = np.full((1, 64, 2), 11, dtype=np.int8)
        htltf = np.full((1, 64, 2), 22, dtype=np.int8)
        stbc_htltf = np.full((1, 64, 2), 33, dtype=np.int8)
        frame = self.make_csi_frame(np.concatenate([lltf, htltf, stbc_htltf], axis=1))
        selected = extract_lltf_iq(frame, mask_first_word=False)
        np.testing.assert_array_equal(selected, lltf)

    def test_non_20mhz_frame_is_rejected(self) -> None:
        raw = np.zeros((1, 64, 2), dtype=np.int8)
        with self.assertRaisesRegex(ValueError, "non-20MHz frame"):
            extract_lltf_iq(self.make_csi_frame(raw, flags=1))

    def test_he_ppdu_is_rejected_for_s3_lltf_model(self) -> None:
        raw = np.zeros((1, 64, 2), dtype=np.int8)
        with self.assertRaisesRegex(ValueError, "unsupported PPDU"):
            extract_lltf_iq(self.make_csi_frame(raw, ppdu=1))

    def test_unknown_raw_width_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported raw subcarrier count"):
            extract_lltf_iq(self.make_csi_frame(np.zeros((1, 96, 2), dtype=np.int8)))


if __name__ == "__main__":
    unittest.main()

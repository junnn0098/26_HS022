"""Strict four-node transport and LLTF-only model-input validator."""

from __future__ import annotations

import argparse
import json
import socket
import time
from collections import Counter, defaultdict

from .adr018 import (
    CANONICAL_SUBCARRIERS,
    LTF_SELECTION_POLICY,
    extract_lltf_iq,
    parse_adr018,
    sequence_gap,
)


def parse_nodes(value: str) -> tuple[int, ...]:
    try:
        nodes = tuple(sorted({int(item.strip()) for item in value.split(",")}))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("nodes must be comma-separated integers") from exc
    if not nodes or any(node < 1 or node > 255 for node in nodes):
        raise argparse.ArgumentTypeError("nodes must be between 1 and 255")
    return nodes


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Require every node and extract only LLTF64 from raw CSI"
    )
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5005)
    parser.add_argument("--nodes", type=parse_nodes, default=(1, 2, 3, 4))
    parser.add_argument("--duration", type=float, default=60.0)
    parser.add_argument("--print-every", type=float, default=10.0)
    parser.add_argument("--min-pps-per-node", type=float, default=15.0)
    parser.add_argument("--max-gap-rate", type=float, default=0.02)
    args = parser.parse_args()
    if args.duration < 10 or args.print_every <= 0:
        parser.error("duration must be >= 10 and print interval must be positive")

    frames: Counter[int] = Counter()
    raw_counts: defaultdict[int, Counter[int]] = defaultdict(Counter)
    ppdu_counts: defaultdict[int, Counter[int]] = defaultdict(Counter)
    flag_counts: defaultdict[int, Counter[int]] = defaultdict(Counter)
    ltf_block_counts: defaultdict[int, Counter[int]] = defaultdict(Counter)
    gaps: Counter[int] = Counter()
    reordered: Counter[int] = Counter()
    invalid: Counter[str] = Counter()
    unexpected_nodes: Counter[int] = Counter()
    first_seen: dict[int, float] = {}
    last_seen: dict[int, float] = {}
    last_sequence: dict[int, int] = {}
    source_ips: defaultdict[int, set[str]] = defaultdict(set)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    sock.bind((args.bind, args.port))
    sock.settimeout(0.25)
    started = time.monotonic()
    deadline = started + args.duration
    next_report = started + args.print_every
    print(
        f"STRICT_LLTF64_VALIDATOR_READY bind={args.bind}:{args.port} "
        f"nodes={args.nodes} duration={args.duration:.1f}s",
        flush=True,
    )

    try:
        while time.monotonic() < deadline:
            try:
                data, sender = sock.recvfrom(65535)
            except socket.timeout:
                pass
            else:
                try:
                    frame = parse_adr018(data)
                except ValueError as exc:
                    invalid[str(exc).split(":", 1)[0]] += 1
                    continue
                if frame.node_id not in args.nodes:
                    unexpected_nodes[frame.node_id] += 1
                    continue
                try:
                    canonical = extract_lltf_iq(frame)
                except ValueError as exc:
                    invalid[str(exc).split(":", 1)[0]] += 1
                    continue
                if canonical.shape[1] != CANONICAL_SUBCARRIERS:
                    invalid["normalization width mismatch"] += 1
                    continue

                now = time.monotonic()
                node = frame.node_id
                first_seen.setdefault(node, now)
                last_seen[node] = now
                source_ips[node].add(sender[0])
                raw_counts[node][frame.subcarriers] += 1
                ppdu_counts[node][frame.ppdu] += 1
                flag_counts[node][frame.flags] += 1
                ltf_block_counts[node][frame.ltf_block_count] += 1
                frames[node] += 1
                previous = last_sequence.get(node)
                if previous is not None:
                    gap = sequence_gap(previous, frame.sequence)
                    if gap < 0:
                        reordered[node] += 1
                    else:
                        gaps[node] += gap
                last_sequence[node] = frame.sequence

            now = time.monotonic()
            if now >= next_report:
                elapsed = max(now - started, 1e-9)
                rates = {node: round(frames[node] / elapsed, 2) for node in args.nodes}
                print(
                    f"LIVE elapsed={elapsed:.1f}s pps={rates} "
                    f"raw={{{', '.join(f'{node}:{dict(raw_counts[node])}' for node in args.nodes)}}}",
                    flush=True,
                )
                next_report = now + args.print_every
    finally:
        sock.close()

    elapsed = max(time.monotonic() - started, 1e-9)
    per_node: dict[str, dict] = {}
    transport_ok = True
    for node in args.nodes:
        valid = frames[node]
        rate = valid / elapsed
        gap_rate = gaps[node] / max(valid + gaps[node], 1)
        seen = valid > 0
        transport_ok &= seen and rate >= args.min_pps_per_node and gap_rate <= args.max_gap_rate
        per_node[str(node)] = {
            "frames": valid,
            "average_pps": round(rate, 3),
            "raw_subcarrier_counts": dict(sorted(raw_counts[node].items())),
            "source_ltf_block_counts": dict(sorted(ltf_block_counts[node].items())),
            "ppdu_counts": dict(sorted(ppdu_counts[node].items())),
            "flags_counts": dict(sorted(flag_counts[node].items())),
            "normalized_subcarriers": CANONICAL_SUBCARRIERS,
            "selected_ltf": "LLTF",
            "sequence_gaps": gaps[node],
            "gap_rate": round(gap_rate, 6),
            "duplicates_or_reordered": reordered[node],
            "first_seen_seconds": (
                round(first_seen[node] - started, 3) if node in first_seen else None
            ),
            "last_seen_age_seconds": (
                round(max(0.0, time.monotonic() - last_seen[node]), 3)
                if node in last_seen else None
            ),
            "source_ips": sorted(source_ips[node]),
        }

    summary = {
        "elapsed_seconds": round(elapsed, 3),
        "required_nodes": list(args.nodes),
        "canonical_subcarriers": CANONICAL_SUBCARRIERS,
        "selected_ltf": "LLTF",
        "ltf_selection_policy": LTF_SELECTION_POLICY,
        "per_node": per_node,
        "invalid_reasons": dict(invalid),
        "unexpected_nodes": dict(unexpected_nodes),
        "thresholds": {
            "min_pps_per_node": args.min_pps_per_node,
            "max_gap_rate": args.max_gap_rate,
        },
    }
    print("FINAL_SUMMARY=" + json.dumps(summary, ensure_ascii=False, separators=(",", ":")))
    if not transport_ok:
        print("RESULT=FAIL_STRICT_4NODE_TRANSPORT_OR_QUALITY")
        return 2
    print("TRANSPORT=PASS_ALL_REQUIRED_NODES")
    print("LTF_SELECTION=PASS_LLTF64_ONLY")
    print("MODEL_INPUT=PASS_CANONICAL_LLTF64")
    print("RESULT=PASS_STRICT_4NODE_LLTF64")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

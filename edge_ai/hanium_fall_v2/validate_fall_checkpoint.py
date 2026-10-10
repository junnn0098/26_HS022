"""Command-line preflight for an external fall/activity checkpoint."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .fall_checkpoint import validate_fall_checkpoint_payload


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check RC6 LLTF64/193-channel fall checkpoint compatibility"
    )
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()

    if not args.checkpoint.is_file():
        parser.error(f"checkpoint not found: {args.checkpoint}")

    import torch

    payload = torch.load(args.checkpoint, map_location=args.device, weights_only=False)
    report = validate_fall_checkpoint_payload(payload, torch)
    report["checkpoint"] = str(args.checkpoint.resolve())
    rendered = json.dumps(report, indent=2, ensure_ascii=False)
    print(rendered)
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(rendered + "\n", encoding="utf-8")
        print(f"REPORT={args.json_output.resolve()}")
    print(f"RESULT={report['result']}")
    return 0 if report["live_ready"] else 3 if report["weights_compatible"] else 2


if __name__ == "__main__":
    raise SystemExit(main())

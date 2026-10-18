"""GitHub Release에 올린 데이터셋 파일을 내려받고 SHA-256을 확인한다.

  python dataset/tools/download.py            # 학습 윈도우 NPZ 4개 (189MB) -> dataset/data/
  python dataset/tools/download.py --v2       # v2 형식 세션 48개 (156MB) -> dataset/v2_sessions/
  python dataset/tools/download.py --raw      # 원본 CSI·관절 좌표 녹화 (788MB) -> dataset/raw/
  python dataset/tools/download.py --list     # 받을 파일 목록만 출력

압축 파일(--v2, --raw)은 받은 뒤 같은 폴더에 풀어 둔다.

표준 라이브러리만 사용한다.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

REPO = "junnn0098/26_HS022"
TAG = "dataset-v1.0"
DATASET_DIR = Path(__file__).resolve().parents[1]
CHECKSUMS = DATASET_DIR / "SHA256SUMS"


def read_checksums() -> dict[str, str]:
    sums = {}
    for line in CHECKSUMS.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            digest, name = line.split(maxsplit=1)
            sums[name.strip().lstrip("*")] = digest
    return sums


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(name: str, target: Path, expected: str) -> None:
    if target.exists() and sha256(target) == expected:
        print(f"ok (cached)  {name}")
        return
    url = f"https://github.com/{REPO}/releases/download/{TAG}/{name}"
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(target.suffix + ".part")
    print(f"downloading  {url}")
    with urllib.request.urlopen(url) as response, partial.open("wb") as handle:
        total = int(response.headers.get("Content-Length") or 0)
        done = 0
        for block in iter(lambda: response.read(1 << 20), b""):
            handle.write(block)
            done += len(block)
            if total:
                print(f"\r  {done / 1e6:7.1f} / {total / 1e6:.1f} MB", end="", flush=True)
    print()
    if sha256(partial) != expected:
        partial.unlink()
        sys.exit(f"checksum mismatch for {name}")
    partial.replace(target)
    print(f"ok           {name}")


def target_for(name: str) -> Path:
    if name.startswith("raw_"):
        return DATASET_DIR / "raw" / name
    if name.startswith("v2_"):
        return DATASET_DIR / "v2_sessions" / name
    return DATASET_DIR / "data" / name


def extract(archive: Path) -> None:
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(archive.parent)
    elif archive.name.endswith(".tar.xz"):
        with tarfile.open(archive) as bundle:
            if hasattr(tarfile, "data_filter"):  # Python 3.12+ / 3.11.4+ / 3.10.12+
                bundle.extractall(archive.parent, filter="data")
            else:
                root = archive.parent.resolve()
                for member in bundle.getmembers():
                    if not (member.isfile() or member.isdir()) or not (root / member.name).resolve().is_relative_to(root):
                        sys.exit(f"unexpected entry in {archive.name}: {member.name}")
                bundle.extractall(archive.parent)
    else:
        return
    print(f"extracted    {archive.name} -> {archive.parent.relative_to(DATASET_DIR.parent)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw", action="store_true", help="원본 녹화 묶음(raw_*.tar.xz)도 받기")
    parser.add_argument("--v2", action="store_true", help="v2 형식 세션 묶음(v2_sessions.zip)도 받기")
    parser.add_argument("--list", action="store_true", help="목록만 출력")
    args = parser.parse_args()

    for name, digest in read_checksums().items():
        if (name.startswith("raw_") and not args.raw) or (name.startswith("v2_") and not args.v2):
            continue
        target = target_for(name)
        if args.list:
            print(f"{digest[:12]}  {name} -> {target.relative_to(DATASET_DIR.parent)}")
            continue
        fetch(name, target, digest)
        extract(target)


if __name__ == "__main__":
    main()

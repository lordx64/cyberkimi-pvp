#!/usr/bin/env python3
"""Copy both sides' harness log dirs into a publishable trace bundle.

Read-only on the sources. Produces:

  traces/<run_id>/raw/kimi/...   raw/altar/...
  traces/<run_id>/checksums.txt  (sha256 of every file in the bundle,
                                  excluding checksums.txt itself)

Usage:
  python3 tools/collect_traces.py --run RUN_ID \
      --kimi-logdir /path/to/kimi/logs --altar-logdir /path/to/altar/logs \
      [--traces-root /data/cyberpvp/traces]
"""
import argparse
import hashlib
import os
import shutil
import sys
from pathlib import Path

CHUNK = 1 << 20


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        while b := f.read(CHUNK):
            h.update(b)
    return h.hexdigest()


def copy_side(src: Path, dst: Path) -> int:
    if not src.is_dir():
        sys.exit(f"error: log dir not found: {src}")
    n = 0
    for root, _, files in os.walk(src):
        for name in files:
            s = Path(root) / name
            rel = s.relative_to(src)
            d = dst / rel
            d.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(s, d)
            n += 1
    return n


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True, help="run id, e.g. 2026-09-25T18-00Z-kimi-vs-altar")
    ap.add_argument("--kimi-logdir", required=False, type=Path)
    ap.add_argument("--altar-logdir", required=False, type=Path)
    ap.add_argument("--traces-root", type=Path, default=Path("/data/cyberpvp/traces"))
    ap.add_argument("--skip-checksums", action="store_true",
                    help="copy raw evidence but do not write checksums.txt yet")
    ap.add_argument("--checksums-only", action="store_true",
                    help="(re)write checksums.txt over current bundle contents only")
    args = ap.parse_args()

    bundle = args.traces_root / args.run
    bundle.mkdir(parents=True, exist_ok=True)

    n = 0
    if not args.checksums_only:
        for side, src in (("kimi", args.kimi_logdir), ("altar", args.altar_logdir)):
            if src is None:
                ap.error(f"--{side}-logdir required unless --checksums-only")
            n += copy_side(src, bundle / "raw" / side)

    if args.skip_checksums:
        print(f"copied {n} files into {bundle} (checksums deferred)")
        return

    lines = []
    for root, _, files in os.walk(bundle):
        for name in sorted(files):
            p = Path(root) / name
            if p.name == "checksums.txt":
                continue
            rel = p.relative_to(bundle)
            lines.append(f"{sha256_file(p)}  {rel}")

    (bundle / "checksums.txt").write_text("\n".join(sorted(lines)) + "\n")
    print(f"copied {n} files into {bundle}")
    print(f"checksums: {len(lines)} entries -> {bundle / 'checksums.txt'}")
    print("next: fill manifest.json, verify results, then git add + commit + push")


if __name__ == "__main__":
    main()

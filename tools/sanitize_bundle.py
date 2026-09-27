#!/usr/bin/env python3
"""Sanitize a CyberPVP evidence bundle before publication.

Scrubs, in place:
  - email addresses            -> <REDACTED-EMAIL>
  - public IPv4 addresses      -> <REDACTED-IP>   (RFC1918/loopback/link-local
                                                   kept: they are docker-internal
                                                   and needed to follow the trace)
  - credential values          -> <REDACTED-KEY>  (the actual API keys, passed
                                                   via --secret, plus common
                                                   token shapes: Bearer, sk-,
                                                   ghp_, AKIA, ...)

Replacements are byte-level on token-like strings only (no quotes/backslashes),
so JSONL lines stay valid JSON. Prints a per-file replacement count report.

Usage: sanitize_bundle.py BUNDLE_DIR --secret VALUE [--secret VALUE ...]
"""
import argparse
import ipaddress
import re
import sys
from pathlib import Path

EMAIL_RE = re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
IPV4_RE = re.compile(rb"\b(?:\d{1,3}\.){3}\d{1,3}\b")
TOKEN_RES = [
    re.compile(rb"Bearer\s+[A-Za-z0-9._~+/=-]{16,}"),
    re.compile(rb"sk-[A-Za-z0-9_-]{20,}"),
    re.compile(rb"ghp_[A-Za-z0-9]{30,}"),
    re.compile(rb"github_pat_[A-Za-z0-9_]{30,}"),
    re.compile(rb"AKIA[0-9A-Z]{16}"),
    re.compile(rb"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}"),  # JWT
]


def is_public_ip(raw: bytes) -> bool:
    try:
        ip = ipaddress.ip_address(raw.decode())
    except ValueError:
        return False
    return ip.is_global


def scrub(data: bytes, secrets: list[bytes]) -> tuple[bytes, int]:
    n = 0
    for s in secrets:
        n += data.count(s)
        data = data.replace(s, b"<REDACTED-KEY>")
    for rx in TOKEN_RES:
        data, k = rx.subn(b"<REDACTED-KEY>", data)
        n += k
    data, k = EMAIL_RE.subn(b"<REDACTED-EMAIL>", data)
    n += k
    data, k = IPV4_RE.subn(lambda m: b"<REDACTED-IP>" if is_public_ip(m.group(0))
                           else m.group(0), data)
    n += k
    return data, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bundle")
    ap.add_argument("--secret", action="append", default=[],
                    help="literal secret value to scrub (repeatable)")
    args = ap.parse_args()
    secrets = [s.encode() for s in args.secret if len(s) >= 8]
    root = Path(args.bundle)
    total = 0
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        data = p.read_bytes()
        if b"\x00" in data[:4096]:  # binary file: skip
            continue
        out, n = scrub(data, secrets)
        if n:
            p.write_bytes(out)
            print(f"{p.relative_to(root)}: {n} replacements")
            total += n
    print(f"TOTAL: {total} replacements in {root}")
    if not total:
        print("NOTE: nothing matched — check that --secret values are correct")


if __name__ == "__main__":
    main()

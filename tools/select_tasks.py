#!/usr/bin/env python3
"""Deterministic CyberGym task selection.

Policy (auditable):
  - Always include tasks already on the blocklist file (kept for continuity).
  - Fill the rest with a stably-seeded uniform sample across tasks.json.
  - Selection rule, seed, and excluded/kept sets are written to stdout JSON,
    so every match manifest can cite exactly how the task list was chosen.

Usage:
  python tools/select_tasks.py tasks.json --count 100 --seed 20260924 \
      --keep-file keep_tasks.txt --out subset100_tasks.txt --report subsets_report.json
"""
import argparse
import json
import random
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tasks_json", type=Path)
    ap.add_argument("--count", type=int, default=100)
    ap.add_argument("--seed", type=int, default=20260924)
    ap.add_argument("--keep-file", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--report", type=Path)
    args = ap.parse_args()

    tasks = json.loads(args.tasks_json.read_text())
    all_ids = [t["task_id"] for t in tasks]

    keep = []
    if args.keep_file and args.keep_file.is_file():
        keep = [l.strip() for l in args.keep_file.read_text().splitlines() if l.strip()]

    pool = sorted(set(all_ids) - set(keep))
    rnd = random.Random(args.seed)
    rnd.shuffle(pool)

    extra_count = max(0, args.count - len(keep))
    chosen = keep + pool[:extra_count]

    args.out.write_text("\n".join(chosen) + "\n")
    report = {
        "policy": "deterministic seeded sample over tasks.json; keep-list preserved",
        "tasks_json_path": str(args.tasks_json),
        "benchmark_total": len(all_ids),
        "selection_seed": args.seed,
        "requested_count": args.count,
        "kept_from_keep_file": sorted(keep),
        "selected_additional": sorted(pool[:extra_count]),
        "final_count": len(chosen),
    }
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if not k.startswith(("kept_", "selected_additional"))}, indent=2))


if __name__ == "__main__":
    main()

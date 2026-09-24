#!/usr/bin/env bash
# Trim a local match bundle into its publishable form:
#   KEEP   manifest.json, checksums.txt, events/, console.log, logs/, transcript.jsonl
#   PRUNE  agents' extracted target work trees (raw/**/gen/), archives, nested VCS dirs
# The full unpruned bundle remains on the bench host for 30 days.
# Usage: bash tools/prune_bundle.sh traces/<run_id>
set -euo pipefail
B="${1:?bundle dir required, e.g. traces/2026-09-24T02-match-ckA-vs-ckB-10}"
[ -d "$B" ] || { echo "no such bundle: $B"; exit 1; }

before=$(du -sh "$B" | cut -f1)

# agent-side gen trees (repo extractions, tarballs)
find "$B/raw" -type d -name gen -prune -exec rm -rf {} + 2>/dev/null || true
# any leftover archives anywhere
find "$B" -type f \( -name '*.tar.gz' -o -name '*.tar' -o -name '*.tgz' -o -name '*.zip' \) -delete
# nested VCS dirs
find "$B" -type d -name .git -prune -exec rm -rf {} + 2>/dev/null || true

after=$(du -sh "$B" | cut -f1)
printf 'pruned %s: %s -> %s\n' "$B" "$before" "$after"
echo "retained files:"
find "$B" -type f | sed "s|^$B/||" | sort

#!/usr/bin/env bash
# Run ON the benchmark box (as ubuntu). Idempotent.
# Installs CyberGym harness and prepares the working environment.
set -euo pipefail

BASE=/data/cyberpvp
REPOS=$BASE/repos
CYBERGYM_DIR=$REPOS/cybergym
VENV=$BASE/venv

mountpoint -q /data || { echo "ERROR: /data is not mounted (bootstrap incomplete?)"; exit 1; }

mkdir -p "$REPOS"
cd "$REPOS"

if [ ! -d "$CYBERGYM_DIR/.git" ]; then
  git clone https://github.com/sunblaze-ucb/cybergym
fi

cd "$CYBERGYM_DIR"
git lfs install

if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
fi

"$VENV/bin/pip" install --upgrade pip
"$VENV/bin/pip" install -e '.[dev,server]'

cat <<EOF

== setup_box OK ==

Next:
  source $VENV/bin/activate
  bash /path/to/this/repo/scripts/download_data.sh --subset

CyberGym harness lives at: $CYBERGYM_DIR
Traces will be written to: $BASE/traces/<run_id>/...
EOF

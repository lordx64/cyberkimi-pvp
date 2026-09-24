#!/usr/bin/env bash
# Download CyberGym benchmark data. Run on the box, as ubuntu.
#
#   --subset   (default) 10 documented demo tasks + their server images (~GBs)
#   --full               ENTIRE benchmark: dataset ~240GB + server data up to ~10TB
#   --binary             binary-only server data ~130GB + full dataset ~240GB
set -euo pipefail

MODE="${1:---subset}"
BASE=/data/cyberpvp
CYBERGYM_DIR=$BASE/repos/cybergym
DATASET_DIR=$CYBERGYM_DIR/cybergym_data
VENV=$BASE/venv

[ -d "$CYBERGYM_DIR" ] || { echo "run setup_box.sh first"; exit 1; }

# The 10 tasks documented in the upstream README (5 solvable, 5 hard).
read -r -d '' SUBSET_TASKS <<'EOF' || true
arvo:47101
arvo:3938
arvo:24993
arvo:1065
arvo:10400
arvo:368
oss-fuzz:42535201
oss-fuzz:42535468
oss-fuzz:370689421
oss-fuzz:385167047
EOF

clone_dataset_repo() {
  if [ ! -d "$DATASET_DIR/.git" ]; then
    # metadata only; LFS payloads pulled explicitly afterwards
    GIT_LFS_SKIP_SMUDGE=1 git clone \
      https://huggingface.co/datasets/sunblaze-ucb/cybergym "$DATASET_DIR"
  fi
  cd "$DATASET_DIR"
  git lfs install
}

case "$MODE" in
  --subset)
    clone_dataset_repo
    echo "== pulling LFS payloads for subset tasks =="
    # include patterns must be exact dir paths: data/<bench>/<id>/**
    INCLUDES=()
    while read -r t; do
      bench="${t%%:*}"; id="${t##*:}"
      INCLUDES+=("data/$bench/$id/**")
    done <<< "$SUBSET_TASKS"
    git lfs pull $(printf -- '--include="%s" ' "${INCLUDES[@]}")
    echo "== verifying payloads are real (not LFS pointers) =="
    BAD=0
    while read -r t; do
      bench="${t%%:*}"; id="${t##*:}"
      f="$DATASET_DIR/data/$bench/$id/repo-vul.tar.gz"
      [ -f "$f" ] || { echo "MISSING $t"; BAD=1; continue; }
      file -b "$f" | grep -q gzip || { echo "POINTER $t"; BAD=1; }
    done <<< "$SUBSET_TASKS"
    [ "$BAD" = 0 ] && echo "all subset payloads verified as real gzip data"

    echo "== downloading subset server images =="
    cd "$CYBERGYM_DIR"
    "$VENV/bin/python" scripts/server_data/download_subset.py
    ;;

  --full)
    read -rp "FULL server data is up to ~10TB. Type 'yes' to continue: " c
    [ "$c" = yes ]
    clone_dataset_repo
    cd "$DATASET_DIR" && git lfs pull          # ~240GB
    cd "$CYBERGYM_DIR"
    "$VENV/bin/python" scripts/server_data/download.py \
      --tasks-file "$DATASET_DIR/tasks.json"
    ;;

  --binary)
    clone_dataset_repo
    cd "$DATASET_DIR" && git lfs pull          # ~240GB
    cd "$CYBERGYM_DIR"
    "$VENV/bin/python" scripts/server_data/download_binary_only_runners.py
    wget -O cybergym-server-data.7z \
      https://huggingface.co/datasets/sunblaze-ucb/cybergym-server-binary/resolve/main/cybergym-server-data.7z
    7z x cybergym-server-data.7z
    ;;

  *)
    echo "usage: $0 [--subset|--full|--binary]" >&2
    exit 2
    ;;
esac

echo "== download_data ($MODE) done =="

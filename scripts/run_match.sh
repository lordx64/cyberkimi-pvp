#!/usr/bin/env bash
# Run one dual-model match: both agents on the same task list, in parallel,
# with a manifest written before anything starts.
#
# This is the orchestration skeleton. The actual per-side launch commands are
# provided via env vars so the same script works with any agent harness:
#
#   KIMI_RUN_CMD  -- command that runs the Kimi agent over $TASK_LIST
#   ALTAR_RUN_CMD -- command that runs the Altar agent over $TASK_LIST
# Each command must write its logs under runs/<run_id>/<side>/logs/
# (the commands receive RUN_ID, SIDE, TASK_LIST, LOG_DIR in their environment).
#
# Usage:
#   bash scripts/run_match.sh RUN_ID TASK_LIST_FILE [DIFFICULTY]
set -euo pipefail

RUN_ID="${1:?run id required, e.g. 2026-09-25T18-00Z-kimi-vs-altar}"
TASK_LIST="${2:?file with one task id per line}"
DIFFICULTY="${3:-level1}"

BASE=/data/cyberpvp
RUN_DIR=$BASE/runs/$RUN_ID
OPS_REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${KIMI_RUN_CMD:?set KIMI_RUN_CMD to the Kimi-side agent launch command}"
: "${ALTAR_RUN_CMD:?set ALTAR_RUN_CMD to the Altar-side agent launch command}"

N_TASKS=$(grep -cve '^\s*$' "$TASK_LIST")
mkdir -p "$RUN_DIR"/{kimi,altar}/logs
cp "$TASK_LIST" "$RUN_DIR/tasks.txt"

# --- manifest: written BEFORE the run starts -----------------------------------
KIMI_MODEL_DESC="${KIMI_MODEL_DESC:-kimi (unset!)}"
ALTAR_MODEL_DESC="${ALTAR_MODEL_DESC:-altar-1 (unset!)}"
CYBERGYM_COMMIT=$(git -C "$BASE/repos/cybergym" rev-parse HEAD 2>/dev/null || echo unknown)
OPS_COMMIT=$(git -C "$OPS_REPO_DIR" rev-parse HEAD 2>/dev/null || echo unknown)

cat > "$RUN_DIR/manifest.json" <<EOF
{
  "run_id": "$RUN_ID",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "running",
  "task_ids": $(grep -v '^\s*$' "$TASK_LIST" | jq -R . | jq -s .),
  "difficulty": "$DIFFICULTY",
  "sides": {
    "kimi":  { "model": "$KIMI_MODEL_DESC",  "endpoint": "${KIMI_ENDPOINT:-redacted}" },
    "altar": { "model": "$ALTAR_MODEL_DESC", "endpoint": "${ALTAR_ENDPOINT:-redacted}" }
  },
  "harness": {
    "cybergym_commit": "$CYBERGYM_COMMIT",
    "ops_repo_commit": "$OPS_COMMIT",
    "agent_framework": "${AGENT_FRAMEWORK:-unset}",
    "scaffolding": "${SCAFFOLDING_DESC:-unset}"
  },
  "budget": { "max_steps": ${MAX_STEPS:-100}, "timeout_s": ${TIMEOUT_S:-3600}, "usd_cap": ${USD_CAP:-25} },
  "seed": ${SEED:-0},
  "results": null
}
EOF
echo "manifest written: $RUN_DIR/manifest.json  ($N_TASKS tasks)"

# --- launch both sides ----------------------------------------------------------
export RUN_ID TASK_LIST="$RUN_DIR/tasks.txt"

SIDE=kimi  LOG_DIR="$RUN_DIR/kimi/logs"  bash -c "$KIMI_RUN_CMD"  > "$RUN_DIR/kimi/console.log"  2>&1 &
PID_KIMI=$!
SIDE=altar LOG_DIR="$RUN_DIR/altar/logs" bash -c "$ALTAR_RUN_CMD" > "$RUN_DIR/altar/console.log" 2>&1 &
PID_ALTAR=$!

echo "kimi pid=$PID_KIMI   altar pid=$PID_ALTAR"
RC_K=0; RC_A=0
wait $PID_KIMI  || RC_K=$?
wait $PID_ALTAR || RC_A=$?
echo "exit codes: kimi=$RC_K altar=$RC_A"

# --- collect + finalize ----------------------------------------------------------
python3 "$OPS_REPO_DIR/tools/collect_traces.py" \
  --run "$RUN_ID" \
  --kimi-logdir "$RUN_DIR/kimi/logs" \
  --altar-logdir "$RUN_DIR/altar/logs" \
  --traces-root "$BASE/traces"

cp "$RUN_DIR/manifest.json" "$BASE/traces/$RUN_ID/manifest.json"
echo "bundle: $BASE/traces/$RUN_ID"
echo "TODO: verify PoCs with upstream scripts/verify_agent_result.py, fill results,"
echo "      then git add traces/$RUN_ID && git commit && git push"

#!/usr/bin/env bash
# Run one dual-model match on the same task list, in parallel.
# Manifest-first: traces/<run_id>/manifest.json exists BEFORE the agents start,
# and both agents append live events to traces/<run_id>/events/<side>.events.jsonl
# so the dashboard can stream the match live.
#
# The per-side agent launch commands come in via env vars and receive
#   RUN_ID SIDE TASK_LIST LOG_DIR EVENTS_DIR WORK_DIR
# in their environment:
#
#   KIMI_RUN_CMD  -- launch command for the kimi-side agent
#   ALTAR_RUN_CMD -- launch command for the altar-side agent
#
# Usage:
#   bash scripts/run_match.sh RUN_ID TASK_LIST_FILE [DIFFICULTY]
set -euo pipefail

RUN_ID="${1:?run id required, e.g. 2026-09-25T18-00Z-kimi-vs-altar}"
TASK_LIST="${2:?file with one task id per line}"
DIFFICULTY="${3:-level1}"

BASE=/data/cyberpvp
OPS_REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR=$BASE/runs/$RUN_ID
BUNDLE=$BASE/traces/$RUN_ID

: "${KIMI_RUN_CMD:?set KIMI_RUN_CMD to the kimi-side agent launch command}"
: "${ALTAR_RUN_CMD:?set ALTAR_RUN_CMD to the altar-side agent launch command}"

N_TASKS=$(grep -cve '^\s*$' "$TASK_LIST")

mkdir -p "$RUN_DIR"/{kimi,altar}/{logs,work}
mkdir -p "$BUNDLE/events"
cp "$TASK_LIST" "$RUN_DIR/tasks.txt"

# --- manifest FIRST (public location) ------------------------------------------
KIMI_MODEL_DESC="${KIMI_MODEL_DESC:-CyberKimi by Adverserial AI (lordx64/cyberkimi)}"
ALTAR_MODEL_DESC="${ALTAR_MODEL_DESC:-Altar-1 (Aikido) (unset!)}"
CYBERGYM_COMMIT=$(git -C "$BASE/repos/cybergym" rev-parse HEAD 2>/dev/null || echo unknown)
OPS_COMMIT=$(git -C "$OPS_REPO_DIR" rev-parse HEAD 2>/dev/null || echo unknown)

cat > "$BUNDLE/manifest.json" <<EOF
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
  "budget": { "max_steps": ${MAX_STEPS:-100000}, "timeout_s": ${TIMEOUT_S:-0}, "max_tokens": ${MAX_TOKENS:-0}, "usd_cap": null,
    "_note": "all values enforced live by the runner (tokens metered + hard cutoff; iters/time capped); 0/null would mean unbounded" },
  "seed": ${SEED:-0},
  "_seed_note": "0 = uncontrolled; sampling params are the API default for both sides",
  "results": null
}
EOF
cp "$BUNDLE/manifest.json" "$RUN_DIR/manifest.json"
echo "manifest (pre-run): $BUNDLE/manifest.json  ($N_TASKS tasks)"

# --- guarantee the judge server is up ---------------------------------------------
if ! pgrep -f "cybergym.server" >/dev/null 2>&1; then
  echo "judge server not running — starting it"
  HOST_GW=$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}')
  export CYBERGYM_API_KEY=$(cut -d= -f2 "$BASE/server.env")
  source "$BASE/venv/bin/activate"
  (cd "$BASE/repos/cybergym" && \
   CYBERGYM_API_KEY=$CYBERGYM_API_KEY nohup python3 -m cybergym.server \
     --host "$HOST_GW" --port 8666 --mask_map_path mask_map.json \
     --log_dir "$BASE/server_poc" --db_path "$BASE/server_poc/poc.db" \
     > "$BASE/server.log" 2>&1 &)
  sleep 5
fi

# --- launch both sides -----------------------------------------------------------
export RUN_ID TASK_LIST="$RUN_DIR/tasks.txt" EVENTS_DIR="$BUNDLE/events"

SIDE=kimi  LOG_DIR="$RUN_DIR/kimi/logs"  WORK_DIR="$RUN_DIR/kimi/work"  \
  bash -c "$KIMI_RUN_CMD"  > "$RUN_DIR/kimi/console.log"  2>&1 &
PID_KIMI=$!
SIDE=altar LOG_DIR="$RUN_DIR/altar/logs" WORK_DIR="$RUN_DIR/altar/work" \
  bash -c "$ALTAR_RUN_CMD" > "$RUN_DIR/altar/console.log" 2>&1 &
PID_ALTAR=$!

echo "kimi pid=$PID_KIMI   altar pid=$PID_ALTAR"
RC_K=0; RC_A=0
wait $PID_KIMI  || RC_K=$?
wait $PID_ALTAR || RC_A=$?
echo "exit codes: kimi=$RC_K altar=$RC_A"

# --- collect raw evidence ---------------------------------------------------------
# agents create root-owned files inside their containers; the collector runs as
# ubuntu, so make the run dir readable first or copy dies on PermissionError
sudo chmod -R a+rX "$RUN_DIR" 2>/dev/null || true
python3 "$OPS_REPO_DIR/tools/collect_traces.py" \
  --run "$RUN_ID" \
  --kimi-logdir "$RUN_DIR/kimi" \
  --altar-logdir "$RUN_DIR/altar" \
  --traces-root "$BASE/traces" \
  --skip-checksums

# finalize manifest status (results stay null until verified PoC scoring is run)
python3 - "$BUNDLE/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["status"] = "complete"
json.dump(m, open(p, "w"), indent=2)
PY

# checksums LAST, over the final bundle state
python3 "$OPS_REPO_DIR/tools/collect_traces.py" \
  --run "$RUN_ID" --traces-root "$BASE/traces" --checksums-only

echo "bundle: $BUNDLE"
echo "NOTE: verify PoCs with upstream scripts/verify_agent_result.py, then git add+commit+push traces/$RUN_ID"

#!/usr/bin/env bash
# Runs every task in $TASK_LIST for one side, sequentially.
# Environment provided by run_match.sh:
#   RUN_ID SIDE TASK_LIST LOG_DIR EVENTS_DIR WORK_DIR
# Model/endpoint config via env:
#   CYBERKIMI_KEY_FILE  (default /data/cyberpvp/secrets/cyberkimi.env)
#   AGENT_BASE_URL      (default https://api.adverserial.ai/v1)
#   AGENT_MODEL         (default lordx64/cyberkimi)
set -uo pipefail

BASE=/data/cyberpvp
OPS=$BASE/ops
SERVER="${CYBERGYM_SERVER:-http://172.17.0.1:8666}"

source $BASE/venv/bin/activate
export CYBERKIMI_KEY_FILE="${CYBERKIMI_KEY_FILE:-$BASE/secrets/cyberkimi.env}"
export CYBERGYM_API_KEY=$(cut -d= -f2 "$BASE/server.env")

echo "[agent_side] side=$SIDE run=$RUN_ID tasks=$(grep -cve '^\s*$' "$TASK_LIST")"
infra_streak=0
while IFS= read -r task; do
  [ -z "${task// }" ] && continue
  safe=$(echo "$task" | tr ':/' '__')
  echo "[agent_side] $SIDE starting $task"
  python3 "$OPS/agents/cyberkimi-agent/run_agent.py" \
    --run-id "$RUN_ID" \
    --side "$SIDE" \
    --task-id "$task" \
    --server "${CYBERGYM_SERVER:-http://172.17.0.1:8666}" \
    --data-dir "$BASE/repos/cybergym/cybergym_data/data" \
    --repo-dir "$BASE/repos/cybergym" \
    --work-dir "$WORK_DIR/$safe" \
    --events-dir "$EVENTS_DIR" \
    --base-url "${AGENT_BASE_URL:-https://api.adverserial.ai/v1}" \
    --model "${AGENT_MODEL:-lordx64/cyberkimi}" \
    --max-iters "${MAX_STEPS:-100000}" \
    --timeout "${TIMEOUT_S:-0}" \
    --max-tokens "${MAX_TOKENS:-0}" \
    >> "$LOG_DIR/agent.log" 2>&1
  rc=$?
  echo "[agent_side] $SIDE finished $task rc=$rc"
  if [ "$rc" -eq 43 ]; then
    # API credits exhausted: abort the side at once, retrying can't fix billing.
    printf '{"ts":"%s","run_id":"%s","side":"%s","task_id":null,"seq":0,"kind":"side_abort","summary":"side aborted: API credits exhausted (429) - top up the wallet and rerun"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%S.%6N+00:00)" "$RUN_ID" "$SIDE" \
      >> "$EVENTS_DIR/$SIDE.events.jsonl"
    echo "[agent_side] $SIDE ABORTING: API credits exhausted"
    break
  fi
  if [ "$rc" -eq 42 ]; then
    # LLM endpoint failure, not a model loss. If it keeps happening the
    # endpoint is down — stop the side instead of failing every remaining task.
    infra_streak=$((infra_streak + 1))
    echo "[agent_side] $SIDE infra failure streak: $infra_streak"
    if [ "$infra_streak" -ge 3 ]; then
      printf '{"ts":"%s","run_id":"%s","side":"%s","task_id":null,"seq":0,"kind":"side_abort","summary":"side aborted: 3 consecutive LLM endpoint failures (infra, not model)"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%6N+00:00)" "$RUN_ID" "$SIDE" \
        >> "$EVENTS_DIR/$SIDE.events.jsonl"
      echo "[agent_side] $SIDE ABORTING: LLM endpoint appears down"
      break
    fi
  else
    infra_streak=0
  fi
done < "$TASK_LIST"
echo "[agent_side] $SIDE done"

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
    --max-iters "${MAX_STEPS:-40}" \
    --timeout "${TIMEOUT_S:-1800}" \
    >> "$LOG_DIR/agent.log" 2>&1
  echo "[agent_side] $SIDE finished $task rc=$?"
done < "$TASK_LIST"
echo "[agent_side] $SIDE done"

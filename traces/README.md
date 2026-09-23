# CyberPVP trace format & integrity protocol

Every dual-model run ("match") produces a bundle at `traces/<run_id>/` that is
committed to this repository and pushed to GitHub. The bundle is the complete,
verifiable evidence for the match: what each model saw, what it did, what it
cost, and how it was scored.

## Bundle layout

```
traces/<run_id>/
├── manifest.json          # run configuration — the "rules of the match"
├── checksums.txt          # sha256 of every other file in the bundle
├── raw/
│   ├── kimi/              # untouched copy of the Kimi-side agent log dir
│   └── altar/             # untouched copy of the Altar-side agent log dir
└── events/
    ├── kimi.events.jsonl  # normalized event stream (optional until adapters land)
    └── altar.events.jsonl
```

`raw/` is authoritative and always present. `events/` is derived for the live
dashboard and replay UI; if it ever disagrees with `raw/`, `raw/` wins.

## manifest.json

```json
{
  "run_id": "2026-09-25T18-00Z-kimi-vs-altar",
  "started_at": "RFC3339",
  "status": "planned | running | complete | aborted",
  "task_ids": ["arvo:10400", "..."],
  "difficulty": "level1",
  "sides": {
    "kimi":  { "model": "CyberKimi by Adverserial AI (lordx64/cyberkimi)", "endpoint": "api.adverserial.ai", "params": {} },
    "altar": { "model": "Altar-1 (Aikido)", "endpoint": "<runpod vllm>", "params": {} }
  },
  "harness": {
    "cybergym_commit": "<git sha>",
    "ops_repo_commit": "<git sha of this repo>",
    "agent_framework": "<name+version>",
    "system_prompt_sha256": "...",
    "scaffolding": "human-readable description or file refs"
  },
  "budget": { "max_steps": 100, "timeout_s": 3600, "usd_cap": 25 },
  "seed": 1234,
  "results": { "kimi": {"solved": 0, "attempted": 0}, "altar": {"solved": 0, "attempted": 0} }
}
```

Rules of the match (normative):

1. Both sides run the **same task list, same difficulty, same budgets**, started
   within 60 s of each other.
2. Model endpoints and parameters are recorded verbatim; API keys are redacted,
   everything else is published.
3. `results` is filled in only after PoC verification with the upstream
   `scripts/verify_agent_result.py`; the raw verifier output goes to
   `raw/<side>/verify/`.

## Normalized event schema (derived, for dashboard/replay)

One JSON object per line, see `schema/event.schema.json`. `kind` is one of:
`run_start, task_assign, llm_request, llm_response, tool_call, tool_result,
poc_submit, verdict, budget_update, run_end`. Large payloads are stored under
`raw/` and referenced as `{ "ref": "raw/<side>/<path>", "sha256": "..." }`.

## Integrity

- `tools/collect_traces.py` copies logs read-only and writes `checksums.txt`.
- Committing + pushing the bundle publicly timestamps the evidence on GitHub.
  For high-stakes matches, additionally: `git tag -s match-<run_id>` (signed tag)
  and/or post the bundle root hash to the live stream before the run starts
  (pre-commitment), then reveal the bundle after.

## Working data vs published evidence

`runs/` (gitignored) is where agent processes write live. `traces/` contains
only curated, checksummed, published bundles.

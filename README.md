# CyberPVP

Live, verifiable dual-model cybersecurity matches on the
[CyberGym](https://github.com/sunblaze-ucb/cybergym) benchmark —
two agents, same tasks, same budget, side-by-side.

Public dashboard: **https://cyberpvp.adverserial.ai**

## Fairness protocol (why results here can be trusted)

Every match publishes a complete evidence bundle to this repo before results
are claimed:

1. A `manifest.json` written **before the run starts**: task list, difficulty,
   both model endpoints, harness git SHAs, scaffolding description, budgets
   (steps / wall-clock / dollars), seed.
2. Both agents run the **same task IDs in parallel** with identical budgets.
3. Raw, unmodified agent logs for **both sides** are copied read-only into
   `traces/<run_id>/raw/` with a `sha256` manifest (`checksums.txt`).
4. Scores come only from the upstream CyberGym PoC verifier
   (`scripts/verify_agent_result.py`).

See [`traces/README.md`](traces/README.md) for the normative format.

## Components

| path | what |
|---|---|
| `infra/terraform/` | the entire AWS benchmark box (1 command to create, 1 to destroy) |
| `scripts/setup_box.sh` | installs the CyberGym harness on the box |
| `scripts/download_data.sh` | CyberGym data: `--subset` (10 tasks) / `--binary` (~370GB) / `--full` (up to ~10TB) |
| `scripts/run_match.sh` | dual-run orchestrator: one command launches both agents + writes manifest + collects traces |
| `tools/collect_traces.py` | read-only log collection + checksums |
| `dashboard/` | FastAPI app + web UI behind nginx for cyberpvp.adverserial.ai |
| `traces/` | published match evidence bundles |

## Bring-up runbook

Prereq: local AWS creds with EC2 rights, terraform ≥ 1.5, key pair at
`~/.ssh/cyberpvp_ed25519` (create: `ssh-keygen -t ed25519 -f ~/.ssh/cyberpvp_ed25519`).

```bash
# 1. provision the box (~5 min)
cd infra/terraform && terraform init && terraform apply

# 2. DNS: A record  cyberpvp.adverserial.ai  ->  $(terraform output -raw public_ip)

# 3. prepare the box
ssh -i ~/.ssh/cyberpvp_ed25519 ubuntu@<public_ip>
git clone <this-repo> /data/cyberpvp/ops && cd /data/cyberpvp/ops
bash scripts/setup_box.sh
bash scripts/download_data.sh --subset
sudo bash dashboard/deploy/install_dashboard.sh
bash dashboard/deploy/init_tls.sh   # after DNS resolves

# 4. dry run a match (agent commands are handed in via env)
KIMI_RUN_CMD='...' ALTAR_RUN_CMD='...' bash scripts/run_match.sh <run_id> tasks.txt

# 5. publish the evidence
git add traces/<run_id> && git commit && git push
```

Security posture: only 22 (SSH), 80/443 (dashboard) are open. The CyberGym
judge server binds to the Docker-internal gateway only — never public —
per upstream guidance.

## Costs (rough, us-east-1)

- `c7i.xlarge` benchmark box: ~$0.18/hr — **stop it when not rehearsing/streaming** (EBS persists)
- 1TB gp3 data volume + root: ~$90/mo
- Elastic IP: free while instance runs
- Altar-1 serving: separate (RunPod B300 class GPU), not part of this repo's AWS spend

If you hit a vCPU quota error on apply: `terraform apply -var instance_type=c7i.4xlarge`.

## Roadmap

- [ ] wire `run_match.sh` to the concrete agent harnesses (dry run on the 10-task subset)
- [ ] normalized event adapters (raw harness logs → `events/*.jsonl`)
- [ ] Altar-1 serving endpoint on RunPod (vLLM, OpenAI-compatible, VPC-peered or TLS)
- [ ] live scoreboard + replay player in the dashboard
- [ ] signed git tags / hash pre-commitment per match

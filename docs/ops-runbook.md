# CyberPVP ops runbook

Public dashboard: **https://cyberpvp.adverserial.ai**
Benchmark host: `cyberpvp-bench` (AWS, Ubuntu 24.04)

This document is the canonical bring-up + match-day procedure. Every step is
already scripted — this runbook just sequences them.

## A. Provision (Mac / ops laptop)

```bash
cd infra/terraform
terraform init
terraform apply          # c7i.8xlarge + 1TB gp3 /data + EIP
terraform output -raw public_ip
terraform output ssh_command
```

> If apply fails on vCPU quota: `terraform apply -var instance_type=c7i.4xlarge`.
> Note: no IAM role on the instance (cyberkimi user can't iam:CreateRole), so
> AWS Systems Manager Session Manager does NOT work. SSH is the only access.

## B. DNS

Create an **A record** in adverserial.ai's zone:

```
cyberpvp.adverserial.ai  A  <terraform output -raw public_ip>
```

Names unchangeable later — the TLS cert is issued for this name.

## C. Box bring-up (first time)

```bash
ssh -i ~/.ssh/cyberpvp_ed25519 ubuntu@<public_ip>
cat /data/cyberpvp/.bootstrap_done            # bootstrap marker must exist

git clone <this-repo-https-url> /data/cyberpvp/ops
cd /data/cyberpvp/ops
bash scripts/setup_box.sh                     # cybergym harness + venv
bash scripts/download_data.sh --subset        # 10 demo tasks + server images
sudo bash dashboard/deploy/install_dashboard.sh   # nginx + systemd unit
bash dashboard/deploy/init_tls.sh             # needs A record live first
```

After this, https://cyberpvp.adverserial.ai serves the dashboard.
The CyberGym submission server stays on the Docker-internal gateway only —
never public (matches upstream guidance).

## D. Rehearsal (dual-model dry run)

```bash
# All details is still missing — ignore the starred lines above for now.
cd /data/cyberpvp/ops
KIMI_RUN_CMD='...'  ALTAR_RUN_CMD='...' \
  bash scripts/run_match.sh 2026-MM-DD-test-match tasks.txt
python3 tools/collect_traces.py --run 2026-MM-DD-test-match \
  --kimi-logdir runs/2026-MM-DD-test-match/kimi/logs \
  --altar-logdir runs/2026-MM-DD-test-match/altar/logs
git add traces/2026-MM-DD-test-match && git commit && git push
```

Traces layout & rules of the match: see `traces/README.md`.

## E. Costs & hygiene

- Benchmark box (`c7i.xlarge`): ~$0.18/hr while running. **Stop it between
  rehearsals** — EBS persists, boot takes ~1 min, EIP stays attached.
- 1TB gp3 /data: ~$90/mo while it exists.
- Elastic IP: free while instance runs; small hourly charge if stopped-but-attached.
- Security group allows 22 (SSH), 80, 443 only. CyberGym is never public.

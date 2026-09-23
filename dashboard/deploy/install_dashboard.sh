#!/usr/bin/env bash
# Install the dashboard on the benchmark box. Run as ubuntu with sudo available.
# Assumes this repo is at /data/cyberpvp/ops.
set -euo pipefail

OPS=/data/cyberpvp/ops
DASH=$OPS/dashboard

sudo apt-get install -y nginx certbot python3-certbot-nginx

if [ ! -d /data/cyberpvp/dashboard-venv ]; then
  python3 -m venv /data/cyberpvp/dashboard-venv
fi
/data/cyberpvp/dashboard-venv/bin/pip install -r "$DASH/requirements.txt"

sudo install -m 644 "$DASH/deploy/cyberpvp-dashboard.service" \
  /etc/systemd/system/cyberpvp-dashboard.service
sudo systemctl daemon-reload
sudo systemctl enable --now cyberpvp-dashboard

sudo install -m 644 "$DASH/deploy/nginx.conf" /etc/nginx/sites-available/cyberpvp
sudo ln -sf /etc/nginx/sites-available/cyberpvp /etc/nginx/sites-enabled/cyberpvp
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

cat <<'EOF'
== dashboard installed on :80 ==

When the A record for cyberpvp.adverserial.ai resolves to this box, run:
  bash dashboard/deploy/init_tls.sh
EOF

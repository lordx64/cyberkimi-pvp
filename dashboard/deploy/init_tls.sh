#!/usr/bin/env bash
# One-time TLS setup — only after DNS (cyberpvp.adverserial.ai) points at this box.
set -euo pipefail
sudo certbot --nginx -d cyberpvp.adverserial.ai --redirect --agree-tos --register-unsafely-without-email
sudo systemctl reload nginx
echo "TLS live: https://cyberpvp.adverserial.ai"

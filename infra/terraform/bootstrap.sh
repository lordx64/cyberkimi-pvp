#!/usr/bin/env bash
# cyberpvp benchmark host bootstrap (runs once as root via EC2 user_data)
set -euxo pipefail

# --- 1. Find and mount the data volume at /data -------------------------------
ROOT_DEV=$(findmnt -no SOURCE / | sed 's/p[0-9]*$//')
DATA_DEV=""
for _ in $(seq 1 60); do
  for dev in /dev/nvme[1-9]n1 /dev/xvdf; do
    if [ -b "$dev" ] && [ "$dev" != "$ROOT_DEV" ]; then
      DATA_DEV=$dev
      break
    fi
  done
  [ -n "$DATA_DEV" ] && break
  sleep 5
done
[ -n "$DATA_DEV" ] || { echo "FATAL: data volume never appeared"; exit 1; }

if ! blkid "$DATA_DEV"; then
  mkfs.ext4 -L cyberpvp-data "$DATA_DEV"
fi

mkdir -p /data
UUID=$(blkid -s UUID -o value "$DATA_DEV")
grep -q "$UUID" /etc/fstab || echo "UUID=$UUID /data ext4 defaults,nofail 0 2" >> /etc/fstab
mount -a

# Ubuntu's system containerd ignores docker.json data-root and stores pull
# content in /var/lib/containerd (root disk). Put it on /data BEFORE docker
# install, or the benchmark's multi-GB images fill the root volume.
mkdir -p /data/containerd
ln -sfn /data/containerd /var/lib/containerd

# --- 2. Base packages ---------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  docker.io \
  git git-lfs \
  python3 python3-venv python3-pip \
  nginx curl jq unzip htop

# --- 3. Docker: store images/containers on the big data volume -----------------
mkdir -p /data/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "data-root": "/data/docker"
}
EOF
systemctl enable --now docker
systemctl restart docker
usermod -aG docker ubuntu || true
id ssm-user >/dev/null 2>&1 && usermod -aG docker ssm-user || true

# --- 4. Working tree on /data ---------------------------------------------------
mkdir -p /data/cyberpvp/{traces,runs,repos}
chown -R ubuntu:ubuntu /data/cyberpvp

date -u > /data/cyberpvp/.bootstrap_done
echo "cyberpvp bootstrap OK"

#!/usr/bin/env bash
set -euo pipefail

echo "[20] Applying basic system tuning..."

timedatectl set-timezone UTC || true

export DEBIAN_FRONTEND=noninteractive
apt-get install -y unattended-upgrades
systemctl enable unattended-upgrades || true

echo "[20] System tuning complete."

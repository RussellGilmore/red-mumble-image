#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Lock polling for apt to ensure no other process is using it before proceeding
echo "[10] Waiting for apt locks to be released..."
while sudo fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "[10] apt is locked by another process; waiting..."
  sleep 5
done

echo "[10] Updating apt and upgrading base packages..."
apt-get update -y
apt-get upgrade -y

echo "[10] Installing baseline utilities..."
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  jq \
  unzip \
  vim

echo "[10] apt baseline complete."

#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

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

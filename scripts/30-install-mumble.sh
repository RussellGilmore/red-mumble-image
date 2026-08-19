#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[30] Installing mumble-server (murmur)..."

# Preseed debconf so the install does NOT prompt for a SuperUser password
# and does NOT auto-start the daemon. Superuser password and startup are
# handled at first boot by cloud-init, after a cert has been obtained.
echo "mumble-server mumble-server/password-set boolean false" | debconf-set-selections
echo "mumble-server mumble-server/use_capabilities boolean false" | debconf-set-selections

apt-get update -y
apt-get install -y mumble-server

# Disable and stop — a public AMI must never ship a running mumble with no
# cert and a default configuration. First boot (cloud-init) enables + starts
# it after certbot obtains a certificate.
systemctl disable mumble-server
systemctl stop mumble-server || true

# Create the directory the deploy-hook will place certs into.
install -d -o mumble-server -g mumble-server -m 0750 /etc/ssl/mumble

echo "[30] mumble-server installed and disabled."

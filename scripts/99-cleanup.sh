#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[99] Cleaning up before snapshot..."

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/red-mumble-staging

# Clear machine-id so instances launched from this AMI get unique IDs.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Clear cloud-init state so it re-runs fresh on first boot of new instances.
cloud-init clean --logs || true

# Remove SSH host keys so each instance regenerates its own.
rm -f /etc/ssh/ssh_host_*

# Clear shell history and logs.
rm -f /root/.bash_history
find /var/log -type f -exec truncate -s 0 {} \;

echo "[99] Cleanup complete."

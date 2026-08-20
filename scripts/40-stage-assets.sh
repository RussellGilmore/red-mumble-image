#!/usr/bin/env bash
set -euo pipefail

STAGING="/tmp/red-mumble-staging"

echo "[40] Installing staged assets from ${STAGING}..."

# certbot deploy-hook: fires only on actual issuance/renewal, copies certs
# to mumble's directory with correct ownership/permissions, restarts mumble.
install -D -o root -g root -m 0755 \
  "${STAGING}/deploy-hook/mumble-certs.sh" \
  /etc/letsencrypt/renewal-hooks/deploy/mumble-certs.sh

# mumble config template (cert paths baked; domain/secrets slotted at runtime).
install -D -o root -g root -m 0644 \
  "${STAGING}/mumble/mumble-server.ini.template" \
  /etc/red-mumble/mumble-server.ini.template

# First-boot script that cloud-init invokes at runtime.
install -D -o root -g root -m 0755 \
  "${STAGING}/first-boot/mumble-first-boot.sh" \
  /usr/local/sbin/mumble-first-boot.sh

echo "[40] Staged assets installed."

#!/usr/bin/env bash
set -euo pipefail

# certbot deploy-hook: runs ONLY when a certificate is actually issued or
# renewed (not on no-op renewal checks). certbot sets $RENEWED_LINEAGE to
# the live directory of the cert that changed, e.g.
#   /etc/letsencrypt/live/mumble.orgychat.org
#
# We copy the cert + key into mumble's own directory with ownership and
# permissions the mumble-server user can read, then restart mumble so it
# picks up the new certificate. Copying (rather than pointing mumble at the
# root-owned /etc/letsencrypt tree) is what avoids the permission problem:
# mumble-server cannot traverse /etc/letsencrypt/{live,archive} directly.

MUMBLE_SSL_DIR="/etc/ssl/mumble"

if [[ -z "${RENEWED_LINEAGE:-}" ]]; then
  echo "[deploy-hook] RENEWED_LINEAGE not set; nothing to do."
  exit 0
fi

echo "[deploy-hook] Deploying renewed cert from ${RENEWED_LINEAGE} to ${MUMBLE_SSL_DIR}"

install -d -o mumble-server -g mumble-server -m 0750 "${MUMBLE_SSL_DIR}"

cp "${RENEWED_LINEAGE}/fullchain.pem" "${MUMBLE_SSL_DIR}/fullchain.pem"
cp "${RENEWED_LINEAGE}/privkey.pem"   "${MUMBLE_SSL_DIR}/privkey.pem"

chown mumble-server:mumble-server "${MUMBLE_SSL_DIR}/fullchain.pem" "${MUMBLE_SSL_DIR}/privkey.pem"
chmod 640 "${MUMBLE_SSL_DIR}/fullchain.pem" "${MUMBLE_SSL_DIR}/privkey.pem"

# Restart mumble so it loads the new cert. Only if it's active — on the very
# first issuance at boot, mumble isn't started yet (first-boot handles that).
if systemctl is-active --quiet mumble-server; then
  echo "[deploy-hook] Restarting mumble-server to load new certificate."
  systemctl restart mumble-server
else
  echo "[deploy-hook] mumble-server not active yet; skipping restart."
fi

echo "[deploy-hook] Done."

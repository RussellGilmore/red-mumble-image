#!/usr/bin/env bash
set -euo pipefail

# certbot deploy-hook: runs ONLY when a certificate is actually issued or
# renewed. certbot sets $RENEWED_LINEAGE to the live dir of the changed cert,
# e.g. /etc/letsencrypt/live/mumble.orgychat.org
#
# Copies cert + key into mumble's directory with ownership/permissions the
# mumble-server user can read, then restarts mumble to load the new cert.

MUMBLE_SSL_DIR="/etc/ssl/mumble"

if [[ -z "${RENEWED_LINEAGE:-}" ]]; then
  echo "[deploy-hook] RENEWED_LINEAGE not set; nothing to do."
  exit 0
fi

echo "[deploy-hook] Deploying cert from ${RENEWED_LINEAGE} to ${MUMBLE_SSL_DIR}"

install -d -o mumble-server -g mumble-server -m 0750 "${MUMBLE_SSL_DIR}"

cp "${RENEWED_LINEAGE}/fullchain.pem" "${MUMBLE_SSL_DIR}/fullchain.pem"
cp "${RENEWED_LINEAGE}/privkey.pem"   "${MUMBLE_SSL_DIR}/privkey.pem"

chown mumble-server:mumble-server "${MUMBLE_SSL_DIR}/fullchain.pem" "${MUMBLE_SSL_DIR}/privkey.pem"
chmod 640 "${MUMBLE_SSL_DIR}/fullchain.pem" "${MUMBLE_SSL_DIR}/privkey.pem"

if systemctl is-active --quiet mumble-server; then
  echo "[deploy-hook] Restarting mumble-server to load new certificate."
  systemctl restart mumble-server
else
  echo "[deploy-hook] mumble-server not active yet; skipping restart."
fi

echo "[deploy-hook] Done."

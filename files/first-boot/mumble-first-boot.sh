#!/usr/bin/env bash
set -euo pipefail

# First-boot orchestration for the Mumble AMI. Invoked by cloud-init (from
# the instance's user-data). Expects /etc/red-mumble/first-boot.env to have
# been written by user-data with:
#   MUMBLE_DOMAIN=mumble.example.org
#   LE_EMAIL=you@example.org
#   MUMBLE_SUPERUSER_PASSWORD=<secret>
#
# Idempotent-ish: if a cert already exists for the domain, certbot will not
# re-issue, and re-running is safe.

ENV_FILE="/etc/red-mumble/first-boot.env"
TEMPLATE="/etc/red-mumble/mumble-server.ini.template"
MUMBLE_INI="/etc/mumble-server.ini"

echo "[first-boot] Starting Mumble first-boot setup."

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[first-boot] ERROR: ${ENV_FILE} not found. User-data must write it." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

: "${MUMBLE_DOMAIN:?MUMBLE_DOMAIN must be set in ${ENV_FILE}}"
: "${LE_EMAIL:?LE_EMAIL must be set in ${ENV_FILE}}"
: "${MUMBLE_SUPERUSER_PASSWORD:?MUMBLE_SUPERUSER_PASSWORD must be set in ${ENV_FILE}}"

# --- 1. Obtain the certificate via DNS-01 (Route53), using the instance role ---
# No port 80 needed; certbot writes a TXT record to Route53 via the instance's
# IAM role. The baked deploy-hook places the cert into /etc/ssl/mumble/.
if [[ ! -d "/etc/letsencrypt/live/${MUMBLE_DOMAIN}" ]]; then
  echo "[first-boot] Requesting certificate for ${MUMBLE_DOMAIN} via DNS-01 (Route53)..."
  certbot certonly \
    --dns-route53 \
    --non-interactive \
    --agree-tos \
    -m "${LE_EMAIL}" \
    -d "${MUMBLE_DOMAIN}"
else
  echo "[first-boot] Certificate for ${MUMBLE_DOMAIN} already exists; skipping issuance."
  # Ensure certs are staged into mumble's dir even if issuance was skipped.
  RENEWED_LINEAGE="/etc/letsencrypt/live/${MUMBLE_DOMAIN}" \
    /etc/letsencrypt/renewal-hooks/deploy/mumble-certs.sh
fi

# --- 2. Render the mumble config ---
echo "[first-boot] Rendering ${MUMBLE_INI}..."
cp "${TEMPLATE}" "${MUMBLE_INI}"
chown root:root "${MUMBLE_INI}"
chmod 640 "${MUMBLE_INI}"

# --- 3. Set the SuperUser password ---
# mumble-server -supw sets the SuperUser password in the server's database.
echo "[first-boot] Setting Mumble SuperUser password..."
mumble-server -ini "${MUMBLE_INI}" -supw "${MUMBLE_SUPERUSER_PASSWORD}"

# --- 4. Enable and start mumble ---
echo "[first-boot] Enabling and starting mumble-server..."
systemctl enable mumble-server
systemctl restart mumble-server

# --- 5. Scrub the secret-bearing env file ---
# The superuser password was consumed; remove the on-disk copy. (It remains
# retrievable via IMDS user-data, an accepted tradeoff for this SSM-gated box.)
echo "[first-boot] Removing ${ENV_FILE}."
rm -f "${ENV_FILE}"

echo "[first-boot] Mumble first-boot setup complete."

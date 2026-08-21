#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Mumble AMI first-boot orchestration.
#
# Invoked by cloud-init from the instance's user-data. Expects user-data to
# have written /etc/red-mumble/first-boot.env with:
#   MUMBLE_DOMAIN=mumble.example.org
#   LE_EMAIL=you@example.org
#   MUMBLE_SUPERUSER_PASSWORD=<secret>
#
# Flow:
#   1. Obtain a cert via DNS-01 (Route53) using the instance IAM role.
#   2. Render /etc/mumble-server.ini from the baked template.
#   3. Start mumble once so it reads superuserpassword= into its database.
#   4. Strip the plaintext password from the ini and restart clean.
#   5. Scrub the on-disk env file.
#
# Renewal thereafter is handled automatically by the certbot systemd timer
# plus the baked deploy-hook (/etc/letsencrypt/renewal-hooks/deploy/).
# ---------------------------------------------------------------------------

ENV_FILE="/etc/red-mumble/first-boot.env"
TEMPLATE="/etc/red-mumble/mumble-server.ini.template"
MUMBLE_INI="/etc/mumble-server.ini"
DEPLOY_HOOK="/etc/letsencrypt/renewal-hooks/deploy/mumble-certs.sh"

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

# ---------------------------------------------------------------------------
# 1. Obtain the certificate via DNS-01 (Route53), using the instance role.
#    No port 80 needed; certbot writes a TXT record to Route53 via the
#    instance's IAM role. The baked deploy-hook places the cert into
#    /etc/ssl/mumble/ on issuance.
# ---------------------------------------------------------------------------
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
  RENEWED_LINEAGE="/etc/letsencrypt/live/${MUMBLE_DOMAIN}" "${DEPLOY_HOOK}"
fi

# ---------------------------------------------------------------------------
# 2. Render the mumble config from the baked template.
# ---------------------------------------------------------------------------
echo "[first-boot] Rendering ${MUMBLE_INI}..."
cp "${TEMPLATE}" "${MUMBLE_INI}"

# Inject the SuperUser password into the placeholder. Using '|' as the sed
# delimiter avoids collisions with '/' in the password. (If your password may
# contain '|', use a different mechanism.)
sed -i "s|__MUMBLE_SUPERUSER_PASSWORD__|${MUMBLE_SUPERUSER_PASSWORD}|" "${MUMBLE_INI}"
chown root:root "${MUMBLE_INI}"
chmod 640 "${MUMBLE_INI}"

# ---------------------------------------------------------------------------
# 3. First start: mumble reads superuserpassword= and hashes it into the DB.
# ---------------------------------------------------------------------------
echo "[first-boot] Enabling and starting mumble-server (initial start to set SuperUser password)..."
systemctl enable mumble-server
systemctl restart mumble-server

# Give mumble a moment to read the password into its database.
sleep 3

# ---------------------------------------------------------------------------
# 4. Strip the plaintext SuperUser password from the ini and restart clean.
#    mumble has now stored the hashed password in its database; the plaintext
#    line must not remain on disk.
# ---------------------------------------------------------------------------
echo "[first-boot] Removing plaintext SuperUser password from ${MUMBLE_INI}..."
sed -i '/^superuserpassword=/d' "${MUMBLE_INI}"
systemctl restart mumble-server

# ---------------------------------------------------------------------------
# 5. Scrub the secret-bearing env file. (The password remains retrievable via
#    IMDS user-data — an accepted tradeoff for this SSM-gated box.)
# ---------------------------------------------------------------------------
echo "[first-boot] Removing ${ENV_FILE}."
rm -f "${ENV_FILE}"

echo "[first-boot] Mumble first-boot setup complete."

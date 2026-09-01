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
# ---------------------------------------------------------------------------

ENV_FILE="/etc/red-mumble/first-boot.env"
TEMPLATE="/etc/red-mumble/mumble-server.ini.template"
MUMBLE_INI="/etc/mumble/mumble-server.ini"
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
fi

# ---------------------------------------------------------------------------
# 2. Place certs into mumble's directory. certbot runs renewal-hooks/deploy/
#    only on renewal, never on initial issuance — so invoke it explicitly.
# ---------------------------------------------------------------------------
echo "[first-boot] Placing certificates into mumble's directory..."
RENEWED_LINEAGE="/etc/letsencrypt/live/${MUMBLE_DOMAIN}" "${DEPLOY_HOOK}"

# ---------------------------------------------------------------------------
# 3. Render the mumble config. mumble-server on Ubuntu 26.04 reads
#    /etc/mumble/mumble-server.ini and runs as the mumble-server user, so the
#    file must be group-readable by mumble-server.
# ---------------------------------------------------------------------------
echo "[first-boot] Rendering ${MUMBLE_INI}..."
install -d -o root -g root -m 0755 /etc/mumble
cp "${TEMPLATE}" "${MUMBLE_INI}"

# Inject the SuperUser password into the placeholder. '|' delimiter avoids
# collisions with '/' in the password.
sed -i "s|__MUMBLE_SUPERUSER_PASSWORD__|${MUMBLE_SUPERUSER_PASSWORD}|" "${MUMBLE_INI}"
# Inject the welcome text (optional; falls back to a generic default).
WELCOME="${MUMBLE_WELCOME_TEXT:-Welcome to this Mumble server.}"
sed -i "s|__MUMBLE_WELCOME_TEXT__|${WELCOME}|" "${MUMBLE_INI}"

# Inject the server password (optional; empty means an open server).
SERVER_PW="${MUMBLE_SERVER_PASSWORD:-}"
sed -i "s|__MUMBLE_SERVER_PASSWORD__|${SERVER_PW}|" "${MUMBLE_INI}"

# Ownership: mumble-server (the service user) must be able to read this.
chown root:mumble-server "${MUMBLE_INI}"
chmod 640 "${MUMBLE_INI}"

# ---------------------------------------------------------------------------
# 4. Start mumble ONCE so it reads superuserpassword= into its database.
#    Clear any prior failed state first, then wait for it to actually become
#    active rather than sleeping a fixed interval.
# ---------------------------------------------------------------------------
echo "[first-boot] Enabling and starting mumble-server..."
systemctl reset-failed mumble-server 2>/dev/null || true
systemctl enable mumble-server
systemctl restart mumble-server

echo "[first-boot] Waiting for mumble-server to become active..."
for i in {1..15}; do
  if systemctl is-active --quiet mumble-server; then
    echo "[first-boot] mumble-server is active."
    break
  fi
  if [[ "${i}" -eq 15 ]]; then
    echo "[first-boot] ERROR: mumble-server did not become active in time." >&2
    systemctl status mumble-server --no-pager >&2 || true
    exit 1
  fi
  sleep 1
done

# Give mumble a moment to read and hash the password into the database.
sleep 2

# ---------------------------------------------------------------------------
# 5. Strip the plaintext SuperUser password and restart clean (once).
# ---------------------------------------------------------------------------
echo "[first-boot] Removing plaintext SuperUser password from ${MUMBLE_INI}..."
sed -i '/^superuserpassword=/d' "${MUMBLE_INI}"
systemctl reset-failed mumble-server 2>/dev/null || true
systemctl restart mumble-server

# Confirm it's still healthy after the final restart.
for i in {1..15}; do
  if systemctl is-active --quiet mumble-server; then
    break
  fi
  if [[ "${i}" -eq 15 ]]; then
    echo "[first-boot] ERROR: mumble-server not active after password strip." >&2
    systemctl status mumble-server --no-pager >&2 || true
    exit 1
  fi
  sleep 1
done

# ---------------------------------------------------------------------------
# 6. Scrub the secret-bearing env file.
# ---------------------------------------------------------------------------
echo "[first-boot] Removing ${ENV_FILE}."
rm -f "${ENV_FILE}"

echo "[first-boot] Mumble first-boot setup complete."

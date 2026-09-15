#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Mumble AMI first-boot orchestration.
#
# Invoked by cloud-init from the instance's user-data. Expects user-data to
# have written /etc/red-mumble/first-boot.env with:
#   MUMBLE_DOMAIN=mumble.example.com
#   LE_EMAIL=you@example.com
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
#    Retries with backoff to ride out transient Let's Encrypt secondary-
#    validation failures
# ---------------------------------------------------------------------------
if [[ ! -d "/etc/letsencrypt/live/${MUMBLE_DOMAIN}" ]]; then
  echo "[first-boot] Requesting certificate for ${MUMBLE_DOMAIN} via DNS-01 (Route53)..."

  CERT_MAX_ATTEMPTS=5
  CERT_RETRY_DELAY=60
  cert_obtained=false

  for attempt in $(seq 1 "${CERT_MAX_ATTEMPTS}"); do
    echo "[first-boot] certbot attempt ${attempt}/${CERT_MAX_ATTEMPTS}..."
    if certbot certonly \
        --dns-route53 \
        --non-interactive \
        --agree-tos \
        -m "${LE_EMAIL}" \
        -d "${MUMBLE_DOMAIN}"; then
      cert_obtained=true
      echo "[first-boot] Certificate obtained on attempt ${attempt}."
      break
    fi
    if [[ "${attempt}" -lt "${CERT_MAX_ATTEMPTS}" ]]; then
      echo "[first-boot] certbot attempt ${attempt} failed; retrying in ${CERT_RETRY_DELAY}s..."
      sleep "${CERT_RETRY_DELAY}"
    fi
  done

  if [[ "${cert_obtained}" != "true" ]]; then
    echo "[first-boot] ERROR: certbot failed after ${CERT_MAX_ATTEMPTS} attempts." >&2
    echo "[first-boot] The certbot renewal timer will keep retrying in the background." >&2
    exit 1
  fi
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

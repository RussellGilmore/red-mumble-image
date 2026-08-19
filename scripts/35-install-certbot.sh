#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[35] Installing certbot and the Route53 DNS plugin..."

apt-get update -y
apt-get install -y certbot python3-certbot-dns-route53

# Enable the renewal timer now; it stays dormant until a cert exists.
# On renewal it runs the deploy-hook staged in script 40.
systemctl enable certbot.timer

echo "[35] certbot + dns-route53 installed; renewal timer enabled."

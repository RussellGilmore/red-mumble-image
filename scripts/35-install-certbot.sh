#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[35] Installing certbot and the Route53 DNS plugin..."

apt-get update -y
apt-get install -y certbot python3-certbot-dns-route53

systemctl enable certbot.timer

echo "[35] certbot + dns-route53 installed; renewal timer enabled."

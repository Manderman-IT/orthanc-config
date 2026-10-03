#!/usr/bin/env bash
# Entry point del cron: certbot sólo renueva si faltan < 30 días para el
# vencimiento, y en ese caso corre install-cert.sh como deploy-hook.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

certbot renew --quiet --deploy-hook "$REPO_DIR/scripts/install-cert.sh"

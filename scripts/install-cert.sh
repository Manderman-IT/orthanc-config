#!/usr/bin/env bash
# Arma el site.pem que monta nginx-proxy (key + fullchain concatenados, igual que
# el target `certs` del makefile) a partir del certificado de Let's Encrypt y
# recarga nginx sin cortar conexiones.
#
# Lo invoca certbot como --deploy-hook (exporta RENEWED_LINEAGE) y también se
# puede correr a mano después de la emisión inicial.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a; source "$REPO_DIR/.env"; set +a

LINEAGE="${RENEWED_LINEAGE:-/etc/letsencrypt/live/$SITE_NAME}"
PEM="$REPO_DIR/$SITE_KEY_CERT_FILE"
CONTAINER="${NGINX_CONTAINER:-nginx-proxy}"

log() { echo "[$(date '+%F %T')] [install-cert] $*"; }

[[ -r "$LINEAGE/privkey.pem" && -r "$LINEAGE/fullchain.pem" ]] \
  || { log "no se encuentra el certificado en $LINEAGE"; exit 1; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cat "$LINEAGE/privkey.pem" "$LINEAGE/fullchain.pem" > "$TMP"

# El pem está montado como archivo suelto (bind mount): hay que reescribirlo en
# el lugar. Un mv/cp que cambie el inode deja al contenedor viendo el viejo.
touch "$PEM"
chmod 600 "$PEM"
cat "$TMP" > "$PEM"
log "actualizado $PEM ($(openssl x509 -in "$LINEAGE/cert.pem" -noout -enddate))"

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  docker exec "$CONTAINER" nginx -t
  docker exec "$CONTAINER" nginx -s reload
  log "nginx recargado"
else
  log "$CONTAINER no está corriendo; toma el certificado nuevo al levantar"
fi

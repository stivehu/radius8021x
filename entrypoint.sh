#!/bin/sh
# The host ./certs directory is read-only and not owned by the freerad user:
# copy it so that the private key is readable by freerad only.
set -e

CERT_SRC=/run/certs
CERT_DST=/etc/freeradius/certs/bkt

for f in ca.pem server.pem server.key dh; do
    test -f "$CERT_SRC/$f" || { echo "Missing certificate: $CERT_SRC/$f (run: ./mkcerts.sh)" >&2; exit 1; }
done

mkdir -p "$CERT_DST"
cp "$CERT_SRC/ca.pem" "$CERT_SRC/server.pem" "$CERT_SRC/server.key" "$CERT_SRC/dh" "$CERT_DST/"
chown -R freerad:freerad "$CERT_DST"
chmod 600 "$CERT_DST/server.key"

exec /docker-entrypoint.sh "$@"

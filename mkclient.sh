#!/bin/bash
# Client (camera) certificate signed by the CA: certs/clients/<identity>.{pem,key,p12}
# <identity> becomes the CN; set it as the EAP identity on the device (check_cert_cn).
set -euo pipefail

test -n "${1:-}" || { echo "Usage: $0 <identity> [p12-password]" >&2; exit 1; }

SCRIPT_DIR="$(dirname "$0")"
CERT_DIR="$SCRIPT_DIR/certs"
DEFAULT_ORG=RADIUS
CLIENT_DAYS=1825
NAME="$1"
P12_PASSWORD="${2:-}"

env_value() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        sed -n "s/^$1=//p" "$SCRIPT_DIR/.env" | tail -n 1
    fi
}

# Subject organization (whom the certificate is issued to): the environment, then .env, then the default
CLIENT_ORG=${CLIENT_ORG:-$(env_value CLIENT_ORG)}
CLIENT_ORG=${CLIENT_ORG:-$DEFAULT_ORG}

cd "$CERT_DIR"
test -f ca.key || { echo "No CA, run first: ./mkcerts.sh" >&2; exit 1; }
mkdir -p clients
umask 077

openssl req -newkey rsa:2048 -nodes -sha256 \
    -keyout "clients/$NAME.key" -out "clients/$NAME.csr" -subj "/O=$CLIENT_ORG/CN=$NAME"
openssl x509 -req -in "clients/$NAME.csr" -CA ca.pem -CAkey ca.key -CAcreateserial \
    -days "$CLIENT_DAYS" -sha256 -out "clients/$NAME.pem" \
    -extfile <(printf '%s\n' \
        "basicConstraints=CA:false" \
        "keyUsage=critical,digitalSignature,keyEncipherment" \
        "extendedKeyUsage=clientAuth")
rm "clients/$NAME.csr"

# Many camera web UIs expect PKCS#12 (key + certificate + CA in one file)
openssl pkcs12 -export -out "clients/$NAME.p12" -inkey "clients/$NAME.key" \
    -in "clients/$NAME.pem" -certfile ca.pem -passout "pass:$P12_PASSWORD"

echo "Done: $CERT_DIR/clients/$NAME.{pem,key,p12} (CA: $CERT_DIR/ca.pem)"

#!/bin/bash
# CA + RADIUS server certificate + DH parameters into certs/.
# An existing CA is never overwritten (that would invalidate every client certificate).
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
CERT_DIR="$SCRIPT_DIR/certs"
DEFAULT_ORG=RADIUS
CA_DAYS=3650
SERVER_DAYS=1825
SERVER_CN="${1:-radius}"
DH_BITS=2048

env_value() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        sed -n "s/^$1=//p" "$SCRIPT_DIR/.env" | tail -n 1
    fi
}

# Issuer organization: the environment, then .env, then the default
CA_ORG=${CA_ORG:-$(env_value CA_ORG)}
CA_ORG=${CA_ORG:-$DEFAULT_ORG}
CA_SUBJECT="/O=$CA_ORG/CN=$CA_ORG 802.1X CA"

cd "$CERT_DIR"
umask 077

if [ ! -f ca.key ]; then
    openssl req -x509 -newkey rsa:4096 -nodes -sha256 -days "$CA_DAYS" \
        -keyout ca.key -out ca.pem -subj "$CA_SUBJECT" \
        -addext "basicConstraints=critical,CA:true" \
        -addext "keyUsage=critical,keyCertSign,cRLSign"
else
    echo "Existing CA: $CERT_DIR/ca.pem"
fi

openssl req -newkey rsa:2048 -nodes -sha256 \
    -keyout server.key -out server.csr -subj "/O=$CA_ORG/CN=$SERVER_CN"
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
    -days "$SERVER_DAYS" -sha256 -out server.pem \
    -extfile <(printf '%s\n' \
        "basicConstraints=CA:false" \
        "keyUsage=critical,digitalSignature,keyEncipherment" \
        "extendedKeyUsage=serverAuth")
rm server.csr

[ -f dh ] || openssl dhparam -out dh "$DH_BITS"

chmod 644 ca.pem server.pem dh

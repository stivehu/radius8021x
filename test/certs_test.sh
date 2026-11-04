#!/bin/bash
# Subject/issuer organization of the generated certificates (CA_ORG, CLIENT_ORG) and the client
# file formats: runs mkcerts.sh and mkclient.sh on copies in a temporary directory, the real
# certs/ is untouched.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
failed=0

# A fresh stack copy in $TMP_ROOT/$1 with optional .env content $2; prints its path
new_stack() {
    local dir="$TMP_ROOT/$1"
    mkdir -p "$dir/certs"
    cp "$SRC_DIR/mkcerts.sh" "$SRC_DIR/mkclient.sh" "$dir/"
    # Skip the slow DH generation: mkcerts.sh keeps an existing dh file
    touch "$dir/certs/dh"
    [ -n "${2:-}" ] && printf '%s\n' "$2" > "$dir/.env"
    echo "$dir"
}

# $1: stack dir, rest: env assignments; runs mkcerts.sh + mkclient.sh test-client
issue() {
    local dir=$1
    shift
    (env "$@" "$dir/mkcerts.sh" && env "$@" "$dir/mkclient.sh" test-client) > "$dir/issue.log" 2>&1
}

# $1: name, $2: certificate, $3: -subject / -issuer, $4: expected value
expect_field() {
    local actual
    actual=$(openssl x509 -in "$2" -noout "$3" -nameopt compat 2>&1)
    actual=${actual#*=}
    if [ "$actual" = "$4" ]; then
        echo "OK   $1: $actual"
    else
        echo "FAIL $1: $actual, expected: $4"
        failed=1
    fi
}

# Defaults: RADIUS on both sides
dir=$(new_stack default)
issue "$dir" || { echo "FAIL default: issuing failed"; cat "$dir/issue.log"; failed=1; }
expect_field default_ca_subject "$dir/certs/ca.pem" -subject "/O=RADIUS/CN=RADIUS 802.1X CA"
expect_field default_server_subject "$dir/certs/server.pem" -subject "/O=RADIUS/CN=radius"
expect_field default_client_issuer "$dir/certs/clients/test-client.pem" -issuer "/O=RADIUS/CN=RADIUS 802.1X CA"
expect_field default_client_subject "$dir/certs/clients/test-client.pem" -subject "/O=RADIUS/CN=test-client"

# Values from .env
dir=$(new_stack dotenv "$(printf 'CA_ORG=ExampleIssuer\nCLIENT_ORG=ExampleCustomer')")
issue "$dir" || { echo "FAIL dotenv: issuing failed"; cat "$dir/issue.log"; failed=1; }
expect_field dotenv_ca_subject "$dir/certs/ca.pem" -subject "/O=ExampleIssuer/CN=ExampleIssuer 802.1X CA"
expect_field dotenv_server_subject "$dir/certs/server.pem" -subject "/O=ExampleIssuer/CN=radius"
expect_field dotenv_client_issuer "$dir/certs/clients/test-client.pem" -issuer "/O=ExampleIssuer/CN=ExampleIssuer 802.1X CA"
expect_field dotenv_client_subject "$dir/certs/clients/test-client.pem" -subject "/O=ExampleCustomer/CN=test-client"

# The environment overrides .env (make client ORG=...)
dir=$(new_stack env_override "$(printf 'CA_ORG=ExampleIssuer\nCLIENT_ORG=ExampleCustomer')")
issue "$dir" CLIENT_ORG=OtherCustomer || { echo "FAIL env_override: issuing failed"; cat "$dir/issue.log"; failed=1; }
expect_field env_override_client_issuer "$dir/certs/clients/test-client.pem" -issuer "/O=ExampleIssuer/CN=ExampleIssuer 802.1X CA"
expect_field env_override_client_subject "$dir/certs/clients/test-client.pem" -subject "/O=OtherCustomer/CN=test-client"

# $1: name, $2: OK condition result (0 = OK), $3: description
expect() {
    if [ "$2" -eq 0 ]; then
        echo "OK   $1: $3"
    else
        echo "FAIL $1: $3"
        failed=1
    fi
}

# Single-file PEM for cameras that take one file without password: certificate, then the
# private key in the traditional (PKCS#1, "BEGIN RSA PRIVATE KEY") format, unencrypted
dir=$(new_stack combined)
issue "$dir" || { echo "FAIL combined: issuing failed"; cat "$dir/issue.log"; failed=1; }
combined="$dir/certs/clients/test-client-cert-key.pem"
[ "$(sed -n 1p "$combined")" = "-----BEGIN CERTIFICATE-----" ]
expect combined_cert_first $? "certificate first"
[ "$(openssl x509 -in "$combined" -outform der | sha256sum)" = "$(openssl x509 -in "$dir/certs/clients/test-client.pem" -outform der | sha256sum)" ]
expect combined_same_cert $? "same certificate as test-client.pem"
grep -q -- "-----BEGIN RSA PRIVATE KEY-----" "$combined" && ! grep -q "ENCRYPTED" "$combined"
expect combined_traditional_key $? "unencrypted traditional RSA key"
[ "$(openssl pkey -in "$combined" -pubout)" = "$(openssl x509 -in "$combined" -noout -pubkey)" ]
expect combined_key_matches $? "the key belongs to the certificate"
[ "$(stat -c %a "$combined")" = "600" ]
expect combined_private $? "mode 600"

exit $failed

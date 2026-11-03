#!/bin/bash
# Subject/issuer organization of the generated certificates (CA_ORG, CLIENT_ORG): runs
# mkcerts.sh and mkclient.sh on copies in a temporary directory, the real certs/ is untouched.
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

exit $failed

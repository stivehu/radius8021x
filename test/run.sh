#!/bin/sh
# EAP-TLS checks against the running radius container (127.0.0.1, localhost client).
# Prerequisite: ./mkclient.sh test-client
set -u

RADIUS_HOST=127.0.0.1
TEST_IDENTITY=test-client
WORK=/tmp/eapol
failed=0

mkdir -p "$WORK"

write_conf() {
    cat > "$WORK/$1.conf" <<EOT
network={
    key_mgmt=IEEE8021X
    eap=TLS
    identity="$2"
    ca_cert="/certs/ca.pem"
    client_cert="/certs/clients/$TEST_IDENTITY.pem"
    private_key="/certs/clients/$TEST_IDENTITY.key"
    eapol_flags=0
}
EOT
}

# $1: name, $2: expected result (SUCCESS / FAILURE)
check() {
    if eapol_test -c "$WORK/$1.conf" -a "$RADIUS_HOST" -s "$RADIUS_SECRET" -t 10 > "$WORK/$1.log" 2>&1; then
        result=SUCCESS
    else
        result=FAILURE
    fi
    if [ "$result" = "$2" ]; then
        echo "OK   $1: $result"
    else
        echo "FAIL $1: $result, expected: $2"
        tail -20 "$WORK/$1.log"
        failed=1
    fi
}

write_conf valid_client "$TEST_IDENTITY"
check valid_client SUCCESS

# check_cert_cn: the certificate CN does not match the identity
write_conf identity_mismatch "other-client"
check identity_mismatch FAILURE

exit $failed

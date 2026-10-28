#!/bin/sh
# EAP-TLS and MAB checks against the running radius container (127.0.0.1, localhost client).
# Prerequisites: ./mkclient.sh test-client, MAB_MAC listed in raddb/authorized_macs
set -u

RADIUS_HOST=127.0.0.1
TEST_IDENTITY=test-client
MAB_MAC=02:00:00:00:00:01
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

# EAP-TLS with $WORK/$1.conf; $2: optional Calling-Station-Id (the supplicant MAC)
eap() {
    eapol_test -c "$WORK/$1.conf" -a "$RADIUS_HOST" -s "$RADIUS_SECRET" -t 10 ${2:+-M "$2"}
}

# MAB request as a switch sends it: User-Name/User-Password = MAC; $1: MAC, $2: Calling-Station-Id
mab() {
    {
        printf 'User-Name = "%s", User-Password = "%s"' "$1" "$1"
        [ -n "$2" ] && printf ', Calling-Station-Id = "%s"' "$2"
        echo
    } | radclient -x -r 1 -t 3 "$RADIUS_HOST" auth "$RADIUS_SECRET" | tee /dev/stderr | grep -q 'Received Access-Accept'
}

# $1: name, $2: expected result (SUCCESS / FAILURE), rest: command
check() {
    name=$1
    expected=$2
    shift 2
    if "$@" > "$WORK/$name.log" 2>&1; then
        result=SUCCESS
    else
        result=FAILURE
    fi
    if [ "$result" = "$expected" ]; then
        echo "OK   $name: $result"
    else
        echo "FAIL $name: $result, expected: $expected"
        tail -20 "$WORK/$name.log"
        failed=1
    fi
}

write_conf valid_client "$TEST_IDENTITY"
check valid_client SUCCESS eap valid_client

# check_cert_cn: the certificate CN does not match the identity
write_conf identity_mismatch "other-client"
check identity_mismatch FAILURE eap identity_mismatch

# A MAB-listed MAC must not bypass the certificate check of an EAP request
check identity_mismatch_listed_mac FAILURE eap identity_mismatch "$MAB_MAC"

# The switch may send the MAC in any format: it is normalized before the lookup
check mab_listed_mac SUCCESS mab 020000000001 "$MAB_MAC"
check mab_unlisted_mac FAILURE mab 020000000002 "02:00:00:00:00:02"
# Only the switch-reported Calling-Station-Id counts, not the User-Name
check mab_listed_user_name_only FAILURE mab 020000000001 ""

exit $failed

#!/bin/sh
# EAP-TLS, EAP-MD5, PEAP-MSCHAPv2 and MAB checks against the running radius container (127.0.0.1, localhost client).
# Prerequisites: ./mkclient.sh test-client, MAB_MAC listed in raddb/authorized_macs,
# MD5_IDENTITY listed in raddb/eap_md5_users (mounted at /eap_md5_users),
# PEAP_IDENTITY listed in raddb/peap_users (mounted at /peap_users)
set -u

RADIUS_HOST=127.0.0.1
TEST_IDENTITY=test-client
MAB_MAC=02:00:00:00:00:01
MD5_IDENTITY=test-md5
MD5_USERS=/eap_md5_users
PEAP_IDENTITY=test-peap
PEAP_USERS=/peap_users
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

# $1: name, $2: identity, $3: password
write_md5_conf() {
    cat > "$WORK/$1.conf" <<EOT
network={
    key_mgmt=IEEE8021X
    eap=MD5
    identity="$2"
    password="$3"
    eapol_flags=0
}
EOT
}

# $1: name, $2: identity, $3: password
write_peap_conf() {
    cat > "$WORK/$1.conf" <<EOT
network={
    key_mgmt=IEEE8021X
    eap=PEAP
    identity="$2"
    password="$3"
    ca_cert="/certs/ca.pem"
    phase2="auth=MSCHAPV2"
    eapol_flags=0
}
EOT
}

# Cleartext-Password of $1 in the users file $2
password_of() {
    sed -n "s/^$1[[:space:]]\+Cleartext-Password[[:space:]]*:=[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$2"
}

# EAP-MD5 with $WORK/$1.conf: no keying material (-n)
eap_md5() {
    eapol_test -c "$WORK/$1.conf" -a "$RADIUS_HOST" -s "$RADIUS_SECRET" -t 10 -n
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

# Type of the server's first EAP request after an EAP-Identity response; $1: identity, $2: expected type.
# EAP-Message: code 2 (Response), id 0, length, type 1 (Identity), identity.
EAP_TYPE_MD5=04
EAP_TYPE_TLS=0d
first_eap_type() {
    identity_hex=$(printf '%s' "$1" | od -An -tx1 | tr -d ' \n')
    length_hex=$(printf '%04x' $((5 + ${#1})))
    printf 'User-Name = "%s", EAP-Message = 0x0200%s01%s, Message-Authenticator = 0x00\n' \
        "$1" "$length_hex" "$identity_hex" \
        | radclient -x -r 1 -t 3 "$RADIUS_HOST" auth "$RADIUS_SECRET" | tee /dev/stderr \
        | grep -qE "EAP-Message = 0x01[0-9a-f]{6}$2"
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

md5_password=$(password_of "$MD5_IDENTITY" "$MD5_USERS")
if [ -z "$md5_password" ] || [ "$md5_password" = "change-me" ]; then
    echo "FAIL eap_md5: set a password for $MD5_IDENTITY in raddb/eap_md5_users"
    failed=1
else
    write_md5_conf md5_valid "$MD5_IDENTITY" "$md5_password"
    check md5_valid SUCCESS eap_md5 md5_valid
    write_md5_conf md5_wrong_password "$MD5_IDENTITY" "wrong-$md5_password"
    check md5_wrong_password FAILURE eap_md5 md5_wrong_password
fi
# Some MD5-only supplicants do not NAK EAP-TLS but restart: EAP-MD5 identities get MD5 first
check md5_offered_first SUCCESS first_eap_type "$MD5_IDENTITY" "$EAP_TYPE_MD5"
check tls_offered_first SUCCESS first_eap_type "$TEST_IDENTITY" "$EAP_TYPE_TLS"
# An identity without a password (e.g. an EAP-TLS device) cannot use EAP-MD5
write_md5_conf md5_unknown_identity "$TEST_IDENTITY" "any-password"
check md5_unknown_identity FAILURE eap_md5 md5_unknown_identity

# PEAP-MSCHAPv2: the device NAKs EAP-TLS and asks for PEAP, the password comes from peap_users
peap_password=$(password_of "$PEAP_IDENTITY" "$PEAP_USERS")
if [ -z "$peap_password" ] || [ "$peap_password" = "change-me" ]; then
    echo "FAIL peap: set a password for $PEAP_IDENTITY in raddb/peap_users"
    failed=1
else
    write_peap_conf peap_valid "$PEAP_IDENTITY" "$peap_password"
    check peap_valid SUCCESS eap peap_valid
    write_peap_conf peap_wrong_password "$PEAP_IDENTITY" "wrong-$peap_password"
    check peap_wrong_password FAILURE eap peap_wrong_password
fi
# An identity without a PEAP password (EAP-TLS or EAP-MD5 device) cannot use PEAP
write_peap_conf peap_unknown_identity "$TEST_IDENTITY" "any-password"
check peap_unknown_identity FAILURE eap peap_unknown_identity
if [ -n "$md5_password" ]; then
    write_peap_conf peap_md5_identity "$MD5_IDENTITY" "$md5_password"
    check peap_md5_identity FAILURE eap peap_md5_identity
fi

exit $failed

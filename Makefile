SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

TEST_IDENTITY := test-client
TEST_OUT := 2>&1 | tee test.out

# certs/ and test/ are existing directories, so the targets must be phony
.PHONY: build start stop restart logs check certs client fetch-clients test test-certs

build:
	docker compose build
start: certs/server.pem raddb/clients.conf raddb/authorized_macs raddb/eap_md5_users raddb/peap_users
	docker compose up -d radius
stop:
	docker compose --profile test down --remove-orphans
restart: stop start
logs:
	docker compose logs -f radius
# Config check inside the container (radiusd -C)
check: certs/server.pem raddb/clients.conf raddb/authorized_macs raddb/eap_md5_users raddb/peap_users
	docker compose run --rm --no-deps radius -C

certs:
	./mkcerts.sh
# Only when missing: an existing server certificate is kept
certs/server.pem:
	./mkcerts.sh
raddb/clients.conf:
	@echo "Missing raddb/clients.conf: cp raddb/clients.conf.example raddb/clients.conf and list your switches"; exit 1
raddb/authorized_macs:
	@echo "Missing raddb/authorized_macs: cp raddb/authorized_macs.example raddb/authorized_macs and list the MAB devices"; exit 1
raddb/eap_md5_users:
	@echo "Missing raddb/eap_md5_users: cp raddb/eap_md5_users.example raddb/eap_md5_users and set the passwords"; exit 1
raddb/peap_users:
	@echo "Missing raddb/peap_users: cp raddb/peap_users.example raddb/peap_users and set the passwords"; exit 1
client:
	@test -n "$(NAME)" || { echo "Usage: make client NAME=<identity> [P12PASS=<password>] [ORG=<organization>]"; exit 1; }
	$(if $(ORG),CLIENT_ORG="$(ORG)") ./mkclient.sh "$(NAME)" "$(P12PASS)"
# Copy certs/clients/ from the RADIUS host (RADIUS_REMOTE in .env)
fetch-clients:
	./fetch-clients.sh

test: certs/server.pem raddb/clients.conf raddb/authorized_macs raddb/eap_md5_users raddb/peap_users
	test -f certs/clients/$(TEST_IDENTITY).pem || ./mkclient.sh $(TEST_IDENTITY)
	docker compose --profile test run --rm --build eapol-test $(TEST_OUT)
# Certificate subject/issuer organization (CA_ORG, CLIENT_ORG), on the host, in a temporary directory
test-certs:
	test/certs_test.sh $(TEST_OUT)

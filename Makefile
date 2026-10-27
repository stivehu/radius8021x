SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

TEST_IDENTITY := test-client
TEST_OUT := 2>&1 | tee test.out

# certs/ and test/ are existing directories, so the targets must be phony
.PHONY: build start stop restart logs check certs client test

build:
	docker compose build
start: certs/server.pem raddb/clients.conf
	docker compose up -d radius
stop:
	docker compose --profile test down --remove-orphans
restart: stop start
logs:
	docker compose logs -f radius
# Config check inside the container (radiusd -C)
check: certs/server.pem raddb/clients.conf
	docker compose run --rm --no-deps radius -C

certs:
	./mkcerts.sh
# Only when missing: an existing server certificate is kept
certs/server.pem:
	./mkcerts.sh
raddb/clients.conf:
	@echo "Missing raddb/clients.conf: cp raddb/clients.conf.example raddb/clients.conf and list your switches"; exit 1
client:
	@test -n "$(NAME)" || { echo "Usage: make client NAME=<identity> [P12PASS=<password>]"; exit 1; }
	./mkclient.sh "$(NAME)" "$(P12PASS)"

test: certs/server.pem raddb/clients.conf
	test -f certs/clients/$(TEST_IDENTITY).pem || ./mkclient.sh $(TEST_IDENTITY)
	docker compose --profile test run --rm --build eapol-test $(TEST_OUT)

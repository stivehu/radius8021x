#!/bin/bash
# Copy the issued device certificates (certs/clients/) from the RADIUS host to this machine.
# Usage: ./fetch-clients.sh [<user>@<radius-host>] [<remote stack dir>]
# Defaults: RADIUS_REMOTE and RADIUS_REMOTE_DIR from the environment or .env
set -euo pipefail
cd "$(dirname "$0")"

DEFAULT_REMOTE_DIR=docker/radius8021x
LOCAL_DIR=certs/clients

env_value() {
    [ -f .env ] && sed -n "s/^$1=//p" .env | tail -n 1
}

remote=${1:-${RADIUS_REMOTE:-$(env_value RADIUS_REMOTE)}}
remote_dir=${2:-${RADIUS_REMOTE_DIR:-$(env_value RADIUS_REMOTE_DIR)}}
remote_dir=${remote_dir:-$DEFAULT_REMOTE_DIR}

if [ -z "$remote" ]; then
    echo "Usage: $0 <user>@<radius-host> [<remote stack dir>] (or set RADIUS_REMOTE in .env)" >&2
    exit 1
fi

mkdir -p "$LOCAL_DIR"
chmod 700 "$LOCAL_DIR"
scp -p "$remote:$remote_dir/$LOCAL_DIR/*" "$LOCAL_DIR/"
ls -l "$LOCAL_DIR"

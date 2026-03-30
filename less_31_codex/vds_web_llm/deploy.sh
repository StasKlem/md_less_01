#!/usr/bin/env sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  printf '%s\n' "Usage: $0 user@host [/srv/vds_web_llm]" >&2
  exit 1
fi

REMOTE="$1"
REMOTE_DIR="${2:-/srv/vds_web_llm}"

ssh "$REMOTE" "cd '$REMOTE_DIR' && git pull --ff-only && docker compose up -d --build --remove-orphans"


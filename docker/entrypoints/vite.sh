#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

mkdir -p /app/tmp

CHECKSUM_FILE="/app/tmp/pnpm_lock_checksum"
NEW_CHECKSUM=$(sha256sum pnpm-lock.yaml 2>/dev/null | awk '{print $1}')

if [ -d "/app/node_modules" ] && [ -f "$CHECKSUM_FILE" ] && [ "$NEW_CHECKSUM" = "$(cat $CHECKSUM_FILE)" ]; then
  echo "Node modules are up to date. Skipping package install."
else
  echo "Node modules are missing or pnpm-lock.yaml has changed. Installing packages..."
  yes | pnpm install
  echo "$NEW_CHECKSUM" > "$CHECKSUM_FILE"
fi

echo "Ready to run Vite development server."

exec "$@"

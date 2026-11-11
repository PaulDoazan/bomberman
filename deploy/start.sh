#!/bin/bash
# Starts the Godot game server on 9090 and nginx on Render's PORT in front of it; the container
# stops (and Render restarts it) as soon as either one exits.
set -euo pipefail

PAGE_URL="${PAGE_URL:-https://pauldoazan.github.io/bomberman/}"
sed -e "s|__PORT__|${PORT:-10000}|" -e "s|__PAGE__|${PAGE_URL}|g" /app/deploy/nginx.conf > /tmp/nginx.conf

PORT=9090 /app/godot --headless --path /app -- --server &
nginx -c /tmp/nginx.conf -g "daemon off;" &

wait -n
exit 1

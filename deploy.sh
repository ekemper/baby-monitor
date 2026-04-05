#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_PASSWORD="$(grep '^PI_PASSWORD=' "$SCRIPT_DIR/server/.env" | cut -d= -f2-)"
if [[ -z "$PI_PASSWORD" ]]; then
  echo "ERROR: PI_PASSWORD not found in server/.env" >&2
  exit 1
fi

PI_USER="pi"
PI_HOST="192.168.0.71"
PI_DIR="/home/pi/baby-monitor"
REMOTE="${PI_USER}@${PI_HOST}"

run_ssh() { sshpass -p "$PI_PASSWORD" ssh -o StrictHostKeyChecking=no "$REMOTE" "$@"; }

echo "==> Pushing to origin…"
cd "$SCRIPT_DIR"
git push

echo "==> Pulling on Pi…"
run_ssh "cd ${PI_DIR} && git clean -fd && git checkout -f && git pull"

echo "==> Ensuring ffmpeg is installed…"
run_ssh "which ffmpeg >/dev/null 2>&1 || sudo apt install -y ffmpeg"

echo "==> Installing Python dependencies…"
run_ssh "TMPDIR=/var/tmp pip3 install --break-system-packages --no-cache-dir -q -r ${PI_DIR}/server/requirements.txt"

echo "==> Syncing .env…"
sshpass -p "$PI_PASSWORD" rsync -az "$SCRIPT_DIR/server/.env" "${REMOTE}:${PI_DIR}/server/.env"

echo "==> Done. To start the server on the Pi:"
echo "    ssh ${REMOTE} 'cd ${PI_DIR}/server && python3 main.py'"

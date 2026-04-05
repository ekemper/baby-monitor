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

cd "$SCRIPT_DIR"
echo "==> Committing changes…"
git add -A
if ! git diff --cached --quiet; then
  git commit -m "deploy: $(date '+%Y-%m-%d %H:%M')"
fi

echo "==> Pushing to origin…"
git push

echo "==> Pulling on Pi…"
run_ssh "cd ${PI_DIR} && git clean -fd && git checkout -f && git pull"

echo "==> Ensuring ffmpeg is installed…"
run_ssh "which ffmpeg >/dev/null 2>&1 || sudo apt install -y ffmpeg"

echo "==> Installing Python dependencies…"
run_ssh "TMPDIR=/var/tmp pip3 install --break-system-packages --no-cache-dir -q -r ${PI_DIR}/server/requirements.txt"

echo "==> Syncing .env…"
sshpass -p "$PI_PASSWORD" rsync -az "$SCRIPT_DIR/server/.env" "${REMOTE}:${PI_DIR}/server/.env"

echo "==> Restarting server…"
run_ssh "pkill -f 'python3 main.py' 2>/dev/null; sleep 1; cd ${PI_DIR}/server && nohup python3 main.py > /tmp/baby-monitor.log 2>&1 &"
sleep 3
echo "==> Checking server…"
run_ssh "tail -5 /tmp/baby-monitor.log"

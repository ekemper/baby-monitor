---
name: deploy-debug
description: >-
  Deploy baby-monitor server to Raspberry Pi and debug connection issues.
  Use when deploying to the Pi, restarting the server, troubleshooting ngrok
  tunnel errors, WebSocket failures, iOS app connection errors (NSURLErrorDomain
  -1011), OOM kills, or checking Pi server health.
---

# Deploy & Debug — Baby Monitor on Raspberry Pi

## Architecture overview

```
[iOS App] --(wss)--> [ngrok cloud] --(http)--> [Pi :8765 aiohttp]
                                                  └── ffmpeg subprocess (V4L2 camera)
```

- Server: `server/main.py` — Python/aiohttp, ffmpeg camera capture, WebSocket at `/stream`, health at `/health`
- Tunnel: pyngrok using system ngrok binary at `/usr/local/bin/ngrok`
- iOS app: hardcoded to `wss://subglobous-pawky-mark.ngrok-free.dev/stream`
- Pi target: `pi@192.168.0.71`, project at `/home/pi/baby-monitor`
- Credentials: `server/.env` contains `NGROK_AUTHTOKEN`, `NGROK_DOMAIN`, `PI_PASSWORD`

## Deploy workflow

### Quick deploy (run the script)

```bash
./deploy.sh
```

This script does: commit local changes → git push → git pull on Pi → ensure ffmpeg → pip install deps → rsync .env → restart server → tail logs.

### Manual deploy (step by step)

Use these when the script fails or you need granular control. All SSH commands use:

```bash
run_ssh() { sshpass -p "$PI_PASSWORD" ssh -o StrictHostKeyChecking=no pi@192.168.0.71 "$@"; }
```

1. **Commit & push locally**
   ```bash
   git add -A && git diff --cached --quiet || git commit -m "deploy: $(date '+%Y-%m-%d %H:%M')" && git push
   ```

2. **Pull on Pi** (force-clean to avoid conflicts)
   ```bash
   run_ssh "cd /home/pi/baby-monitor && git clean -fd && git checkout -f && git pull"
   ```

3. **Install Python deps** (TMPDIR on disk, not tmpfs)
   ```bash
   run_ssh "TMPDIR=/var/tmp pip3 install --break-system-packages --no-cache-dir -q -r /home/pi/baby-monitor/server/requirements.txt"
   ```

4. **Sync .env**
   ```bash
   sshpass -p "$PI_PASSWORD" rsync -az server/.env pi@192.168.0.71:/home/pi/baby-monitor/server/.env
   ```

5. **Restart server**
   ```bash
   run_ssh "pkill -f 'python3 main.py' 2>/dev/null; sleep 1; cd /home/pi/baby-monitor/server && nohup python3 main.py > /tmp/baby-monitor.log 2>&1 &"
   ```

6. **Verify** (wait ~15s for ngrok tunnel to establish)
   ```bash
   sleep 15
   run_ssh "tail -20 /tmp/baby-monitor.log"
   ```

**IMPORTANT**: The nohup SSH command may hang if SSH keeps waiting for child file descriptors. If it doesn't return, `Ctrl-C` and verify separately with `run_ssh "pgrep -a python3"`.

## Debug playbook

When something goes wrong, work through this decision tree:

### 1. Is the ngrok tunnel alive?

```bash
curl -s -o /dev/null -w "%{http_code}" -H "ngrok-skip-browser-warning: true" https://subglobous-pawky-mark.ngrok-free.dev/health
```

| Result | Meaning | Action |
|--------|---------|--------|
| `200` + JSON | Healthy | Tunnel and server are fine; issue is iOS-side |
| `404` + `ERR_NGROK_3200` | Tunnel offline | Server/ngrok not running → go to step 2 |
| `502` | Tunnel up, server down | aiohttp crashed but ngrok is alive → go to step 3 |
| Connection refused | ngrok domain DNS issue | Wait and retry; check ngrok status page |

### 2. Is the server process running?

```bash
run_ssh "pgrep -a python3; echo '---'; pgrep -a ngrok"
```

- **Neither running**: Server crashed or was never started → restart (step 5 of deploy)
- **python3 running, no ngrok**: pyngrok failed to launch ngrok → check logs (step 3)
- **Both running**: Tunnel may not have registered with ngrok cloud → check logs

### 3. Read the server log

```bash
run_ssh "tail -30 /tmp/baby-monitor.log"
```

Common log patterns and fixes:

| Log message | Cause | Fix |
|-------------|-------|-----|
| `Downloading ngrok ...` then silence/Killed | OOM — pyngrok downloading ngrok binary | Verify `/usr/local/bin/ngrok` exists. Code should use `conf.get_default().ngrok_path = shutil.which("ngrok")` |
| `No module named 'pyngrok'` | Deps not installed | `TMPDIR=/var/tmp pip3 install --break-system-packages -r requirements.txt` |
| `ffmpeg not found` | ffmpeg not installed | `sudo apt install -y ffmpeg` |
| `error while attempting to bind on address` | Port 8765 in use | `run_ssh "lsof -ti:8765 \| xargs kill -9"` then restart |
| `ffmpeg process exited unexpectedly` | Camera not available | Check `run_ssh "ls -la /dev/video0"` and `run_ssh "v4l2-ctl --list-devices"` |
| `Failed to start ngrok tunnel` | Auth or config issue | Verify `.env` has correct `NGROK_AUTHTOKEN` and `NGROK_DOMAIN` |
| `ERR_NGROK_108` from ngrok logs | Tunnel session limit (free tier: 1 agent) | Kill any other ngrok processes: `run_ssh "killall ngrok 2>/dev/null"` then restart |

### 4. iOS app `-1011` "bad response from server"

This means the WebSocket handshake got a non-101 HTTP response. Root causes:

1. **Tunnel offline** (most common) — follow steps 1-3 above
2. **Missing ngrok-skip-browser-warning header** — the iOS `WebSocketManager.connect()` must set `request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")` on the `URLRequest`
3. **ngrok interstitial page** — free-tier ngrok shows a browser warning page for the first request. The header above bypasses it.

### 5. Pi resource constraints

The Pi Zero 2W has ~427MB RAM and `/tmp` is a small tmpfs.

- **pip install "No space left on device"**: Always use `TMPDIR=/var/tmp` and `--no-cache-dir`
- **Process killed by OOM**: Check `run_ssh "dmesg | tail -20"` for OOM messages. Ensure pyngrok uses system ngrok binary (not downloading its own).
- **npm/esbuild SIGILL**: Don't build Node.js projects on the Pi — it's ARM and esbuild ships x86 binaries in some contexts.

### 6. SSH / connectivity issues

- **Pi not reachable**: `ping 192.168.0.71` — ensure Pi is on same network
- **sshpass not installed**: `brew install hudochenkov/sshpass/sshpass`
- **deploy.sh "PI_PASSWORD: unbound variable"**: Ensure `server/.env` has `PI_PASSWORD=<value>` (no quotes, no spaces around `=`)
- **git pull conflict on Pi**: The script runs `git clean -fd && git checkout -f` before pull to handle this

### 7. End-to-end smoke test

After deploy, run this sequence to verify the full path:

```bash
# 1. Server process alive?
run_ssh "pgrep -a python3 && pgrep -a ngrok"

# 2. Local health check on Pi?
run_ssh "curl -s http://localhost:8765/health"

# 3. Remote health check through tunnel?
curl -s -H "ngrok-skip-browser-warning: true" https://subglobous-pawky-mark.ngrok-free.dev/health

# 4. WebSocket test (if wscat is available)?
wscat -c "wss://subglobous-pawky-mark.ngrok-free.dev/stream" --header "ngrok-skip-browser-warning: true"
```

Expected healthy output for step 3: `{"status": "ok", "viewers": 0, "uptime_seconds": ...}`

## Quick reference

| Item | Value |
|------|-------|
| Pi address | `pi@192.168.0.71` |
| Pi project dir | `/home/pi/baby-monitor` |
| Server log | `/tmp/baby-monitor.log` on Pi |
| Server port | 8765 |
| ngrok domain | `subglobous-pawky-mark.ngrok-free.dev` |
| Health endpoint | `GET /health` |
| Stream endpoint | `WS /stream` |
| Camera device | `/dev/video0` |
| Credentials file | `server/.env` (gitignored) |

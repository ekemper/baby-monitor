# iOS Viewer App — Phase 1: Server Enhancements

**Master plan:** [ios-viewer-PLAN.md](ios-viewer-PLAN.md)
**Phase:** 1 of 4
**Prerequisites:** None — this phase has no dependencies
**Parallel tracks:** No — sequential
**Estimated scope:** medium

## Summary

Enhance the Python/aiohttp baby monitor server to support multiple concurrent WebSocket viewers, provide an HTTP health-check endpoint, integrate pyngrok for automatic ngrok tunnel startup with a reserved domain, and add WebSocket ping/pong keepalive. After this phase, the React client still works unchanged, multiple browsers can view simultaneously, and the server self-manages its ngrok tunnel.

## Context for this phase

The baby monitor is a USB webcam → Python server → WebSocket → browser viewer system. The server (`server/main.py`) uses aiohttp to capture frames via OpenCV in a daemon thread, encode them as JPEG, and send binary WebSocket frames to a single connected client. A new connection closes the previous one.

This phase modifies the server to:
- Allow any number of simultaneous viewers (iOS app + browser + more)
- Expose a health endpoint the iOS app uses to validate connectivity before opening WebSocket
- Start an ngrok tunnel automatically so there's no manual `ngrok http 8765` step
- Send WebSocket pings so both sides detect dead connections promptly

## Technical implementation detail

### 1. Layout

All changes are in `server/` plus root-level config files:

```
server/
  main.py              (MOD — primary changes)
  requirements.txt     (MOD — new dependencies)
  .env.example         (NEW — env var template)
.gitignore             (MOD — add server/.env)
README.md              (MOD — updated instructions)
```

### 2. Data and APIs

#### Existing (unchanged)

- **`GET /stream` (WebSocket upgrade)** — binary JPEG frames, one frame per WebSocket message. No application-level protocol change.

#### New endpoints

**`GET /health`**

```
Response 200:
{
  "status": "ok",
  "viewers": 3,
  "uptime_seconds": 1842.7
}
Content-Type: application/json
```

Returns current viewer count and server uptime. The iOS app calls this to verify the server is reachable before attempting a WebSocket connection.

#### Environment variables (loaded from `server/.env` via python-dotenv)

| Variable | Required | Description |
|----------|----------|-------------|
| `NGROK_AUTHTOKEN` | Yes (for ngrok) | ngrok authentication token from dashboard |
| `NGROK_DOMAIN` | Yes (for ngrok) | Reserved domain, e.g. `subglobous-pawky-mark.ngrok-free.dev` |

If neither variable is set, the server starts without ngrok (local-only mode, same as current behavior). This keeps the server usable for local development.

### 3. Data flow

#### Multi-viewer broadcast

Current single-client flow:
```
capture_loop → frame_queue → send_loop → single ws.send_bytes()
```

New multi-viewer flow:
```
capture_loop → frame_queue → broadcast_loop → for ws in connected_clients: ws.send_bytes()
```

Implementation:
- Replace `current_client: Optional[WebSocketResponse]` with `connected_clients: set[web.WebSocketResponse]`
- Replace the per-client `send_loop` with a single `broadcast_loop` coroutine that reads from the frame queue and sends to all clients. Failed sends remove the client from the set.
- `stream_handler` adds the new WebSocket to `connected_clients` on connect and removes it on disconnect. No longer closes existing clients.

#### Broadcast loop pseudocode

```python
async def broadcast_loop(app: web.Application) -> None:
    frame_queue = app["frame_queue"]
    loop = asyncio.get_event_loop()
    while True:
        frame = await loop.run_in_executor(None, frame_queue.get)
        dead = []
        for ws in connected_clients:
            try:
                await ws.send_bytes(frame)
            except Exception:
                dead.append(ws)
        for ws in dead:
            connected_clients.discard(ws)
```

Start this as a background task in `app.on_startup`.

#### WebSocket ping/pong

Use aiohttp's built-in `heartbeat` parameter on `WebSocketResponse`:

```python
ws = web.WebSocketResponse(heartbeat=20.0)
```

This is the simplest approach — aiohttp sends pings at the interval and closes the connection if pong is not received within the next interval.

#### ngrok integration flow

On startup (in `main()`):
1. Load `.env` via `dotenv.load_dotenv(dotenv_path=os.path.join(SERVER_DIR, ".env"))`
2. Read `NGROK_AUTHTOKEN` and `NGROK_DOMAIN` from `os.environ`
3. If both are set:
   a. `ngrok.set_auth_token(authtoken)`
   b. `tunnel = ngrok.connect(addr=str(PORT), proto="http", hostname=ngrok_domain)`
   c. Store `tunnel.public_url` in `app["public_url"]`
   d. Log: `"ngrok tunnel active: {public_url}"`
4. If not set: log `"ngrok not configured — running in local-only mode"`, set `app["public_url"] = None`

On shutdown: `ngrok.disconnect(tunnel.public_url)` and `ngrok.kill()` in `app.on_cleanup`.

### 4. Integrations

**pyngrok** (`pyngrok>=7.0.0`): wraps the ngrok agent binary. On first import it downloads the ngrok binary to `~/.ngrok2/` if not present. `ngrok.connect()` starts a tunnel and returns a `NgrokTunnel` object with `.public_url`. Auth token must be set before connecting.

**python-dotenv** (`python-dotenv>=1.0.0`): loads `.env` file into `os.environ`. Call `load_dotenv()` before reading env vars.

### 5. Frontend integration

No changes to the React client. The existing `client/src/components/VideoStream.tsx` connects to the same `/stream` WebSocket. Multi-viewer support is transparent — the server no longer closes the old client when a new one connects, so the browser and iPhone can view simultaneously.

## Deliverables Manifest

1. MOD  `server/main.py` — Replace single-client with `connected_clients: set`, add `broadcast_loop` as background task, add `/health` handler (returns JSON with viewer count and uptime), integrate pyngrok tunnel on startup with graceful fallback, use `heartbeat=20.0` on WebSocketResponse, load `.env` with python-dotenv
2. MOD  `server/requirements.txt` — Add: `pyngrok>=7.0.0`, `python-dotenv>=1.0.0`
3. NEW  `server/.env.example` — Contains `NGROK_AUTHTOKEN=your-token-here` and `NGROK_DOMAIN=subglobous-pawky-mark.ngrok-free.dev` with comments explaining each
4. MOD  `.gitignore` — Add `server/.env` line to prevent committing secrets
5. MOD  `README.md` — Update "Run locally" section (no change), replace "Run with ngrok" section with new integrated flow (copy `.env.example` → `.env`, fill in values, start server with `python main.py`), document `/health` endpoint, note multi-viewer support

**Implementation protocol:** The implementing agent must follow the `plan-implementation` cursor rule when executing this phase.

## Acceptance criteria

- [ ] Multiple WebSocket clients can connect to `/stream` simultaneously and all receive frames
- [ ] Disconnecting one client does not affect other connected clients
- [ ] `GET /health` returns 200 with JSON containing `status`, `viewers`, and `uptime_seconds`
- [ ] Server starts without ngrok when `NGROK_AUTHTOKEN` / `NGROK_DOMAIN` are not set (local-only mode)
- [ ] Server starts ngrok tunnel automatically when env vars are set, and logs the public URL
- [ ] Dead WebSocket connections are cleaned up (no zombie entries in `connected_clients`)
- [ ] Existing React client (`client/`) works unchanged with the modified server

## Test plan

1. **Multi-viewer test:**
   - Start server: `cd server && python main.py`
   - Open `ws://localhost:8765/stream` in two separate browser tabs (use browser dev tools or `websocat ws://localhost:8765/stream`)
   - Verify both receive binary frames
   - Close one tab; verify the other continues receiving

2. **Health endpoint:**
   - `curl http://localhost:8765/health`
   - Verify JSON response with `status: "ok"` and correct `viewers` count
   - Connect a WebSocket client, re-check `/health` — `viewers` should increment

3. **ngrok tunnel:**
   - Create `server/.env` with valid `NGROK_AUTHTOKEN` and `NGROK_DOMAIN`
   - Start server, verify tunnel log message
   - Open `https://subglobous-pawky-mark.ngrok-free.dev/` in a browser → should serve the React app
   - Open `https://subglobous-pawky-mark.ngrok-free.dev/health` → should return health JSON
   - Verify WebSocket stream works over `wss://subglobous-pawky-mark.ngrok-free.dev/stream`

4. **Local-only mode:**
   - Without `.env` file, start server
   - Verify log says "ngrok not configured — running in local-only mode"
   - Verify local WebSocket and health endpoint still work

5. **React client regression:**
   - `cd client && npm run dev`
   - Open Vite dev URL → verify video stream displays as before

## Interface contract (for subsequent phases)

- **Multi-viewer:** Any number of WebSocket clients can connect to `/stream` simultaneously. The server broadcasts frames to all.
- **Health API:** `GET /health` → `{"status": "ok", "viewers": <int>, "uptime_seconds": <float>}` with status 200.
- **Public URL:** When ngrok is active, the server's public URL is `https://<NGROK_DOMAIN>`. WebSocket is at `wss://<NGROK_DOMAIN>/stream`.
- **Ping/pong:** Server sends WebSocket pings every 20s. Clients should respond with pong (most WebSocket implementations do this automatically).

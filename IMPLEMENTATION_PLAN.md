# Baby Monitor: Video-Only Implementation Plan

## Overview

**Goal:** Python server captures video from a USB webcam and streams it to a React app over WebSockets. Video only. Local only: no deployment, no auth, no state, no database, no users.

**Scope (decided):**
- **Video only** — no audio in this version.
- **Local only** — server and browser on the same machine; bind `127.0.0.1`; client uses `ws://localhost:8765/stream`.
- **No deployment** — run server and React dev server locally.
- **No auth** — no tokens or login.

**Stack:**
- **Backend:** Python 3.10+, **websockets** (standalone), asyncio. No HTTP endpoints; WebSocket-only.
- **Capture:** OpenCV (cv2) for USB camera.
- **Transport:** WebSocket on port **8765**, path **/stream**. One message = one raw JPEG binary frame.
- **Frontend:** React (Vite), WebSocket API, `<img>` + `URL.createObjectURL` for MJPEG display.

---

## Architecture

```
┌─────────────────┐     USB      ┌──────────────────────────────────┐     WebSocket      ┌─────────────────┐
│  USB Webcam     │──────────────▶│  Python Server (main.py)          │◀──────────────────▶│  React App      │
│  (video)        │              │  - OpenCV capture (index 0)         │   ws://localhost   │  - WS client    │
└─────────────────┘              │  - MJPEG encode → queue (max 2)    │   :8765/stream     │  - <img> display │
                                  │  - Single client; raw JPEG frames   │   raw JPEG        │  - Minimal state │
                                  └──────────────────────────────────┘                   └─────────────────┘
```

---

## Phase 1: Python Server – Video Capture & WebSocket

### 1.1 Dependencies

- **opencv-python** — USB camera (`cv2.VideoCapture`).
- **websockets** — WebSocket server only (no FastAPI/aiohttp).
- **asyncio** — Capture in thread, WebSocket in main loop.

### 1.2 Video Pipeline (decided)

| Step | Decision | Notes |
|------|----------|--------|
| Device | **Camera index `0`** (hardcoded) | No env var or CLI. |
| Resolution / FPS | **640×480 @ 15 FPS** | Constants at top of `main.py`. |
| Capture failure | **Exit with a clear message** | If `cv2.VideoCapture.open()` fails (no camera, in use, wrong index), exit; no retry loop. |
| Bad frame | **Skip and continue** | If `cv2.read()` returns `False` or empty/corrupt frame, skip that frame; no retry. |
| No clients | **Keep capturing and dropping** | When zero clients are connected, keep capturing; drop frames into a bounded queue. First frame is ready when a client connects. |
| Encode | **MJPEG in-memory** | `cv2.imencode('.jpg', frame)[1].tobytes()`. |
| Send | **One WebSocket message = one raw JPEG** (binary) | No JSON envelope, no length header. |
| Backpressure | **Bounded queue (maxsize 2)** | Drop oldest frames; always send latest. |

### 1.3 Server Structure (decided)

- **Single file:** `server/main.py` — capture loop + WebSocket server in one file. No `config.py`, no `capture/video.py`, no `stream/ws_handler.py` for this version.
- **Configuration:** Constants at top of `main.py`: camera index `0`, width `640`, height `480`, FPS `15`, host `127.0.0.1`, port `8765`, path `/stream`.
- **No HTTP:** WebSocket-only server; no `GET /` or `/health`.
- **Single client:** Support one connected WebSocket at a time. When that client disconnects, remove it; when send fails, remove client and continue (no log).
- **Concurrency:** Video capture runs in a thread (blocking `cv2.read()`); encode and put into `queue.Queue(maxsize=2)`. Main thread runs asyncio WebSocket server; worker pulls from queue and sends to the single client. Use `loop.run_in_executor` when blocking on queue get if needed.

### 1.4 Message Protocol

- **Wire format:** Each WebSocket message is exactly one raw JPEG binary frame. Client treats each binary message as JPEG bytes.

---

## Phase 2: React App – WebSocket Client & Video Display

### 2.1 Dependencies

- **React** (Vite).
- **WebSocket API** — no extra WS library.
- **Blob / URL.createObjectURL** — display MJPEG in `<img>`.

### 2.2 Connection (decided)

| Item | Decision |
|------|----------|
| WebSocket URL | **Hardcoded `ws://localhost:8765/stream`** |
| When to connect | **On mount** — no "Start stream" button. |
| Reconnection | **None** — try once on mount; if connection fails or drops, show a simple message; do not auto-retry. |
| Startup order | **User starts Python server, then opens the React app.** No client retry logic. |
| Connection state | **Minimal:** plain text "Connecting…" or "Disconnected". When live, show video only (or video + "Live" if desired). |

### 2.3 Video Display (decided)

| Item | Decision |
|------|----------|
| Element | **`<img src={objectURL}>`** — not canvas. |
| Object URL lifecycle | **Revoke previous `objectURL`** before assigning the new one when a new JPEG blob arrives (avoid memory growth). |
| Invalid message | **Skip update; keep last valid frame.** No placeholder or error image. |
| Layout | **Constrain size** — e.g. `max-width: 100%` so the page doesn’t overflow on small/large screens. |

### 2.4 React Structure (minimal)

```
baby-monitor/
├── client/
│   ├── src/
│   │   ├── App.tsx
│   │   ├── main.tsx
│   │   ├── index.css
│   │   └── components/
│   │       └── VideoStream.tsx   # WebSocket + <img> + "Connecting…" / "Disconnected"
│   ├── package.json
│   └── ...
```

No separate `config.ts`, `useWebSocketStream.ts`, or `ConnectionStatus.tsx` required for minimal version; logic can live in `VideoStream.tsx`.

### 2.5 Edge Cases (decided)

- **Tab in background:** Ignore; keep receiving frames as-is.
- **Port and path:** Fixed — port **8765**, path **/stream** on both server and client.

---

## Phase 3: Local Run Only (No Deployment)

- **Server:** Bind to **127.0.0.1:8765**. No CORS (no HTTP). No auth.
- **Client:** Served by Vite dev server (e.g. localhost:5173); connects to `ws://localhost:8765/stream`.
- **No production deployment, no HTTPS/WSS, no nginx** in this version.

---

## Implementation Order

| # | Task | Deliverable |
|---|------|-------------|
| 1 | Python: Single `main.py` — OpenCV capture (index 0, 640×480 @ 15 FPS), MJPEG encode, bounded queue (maxsize 2), WebSocket server on 127.0.0.1:8765/stream, single client, raw JPEG frames | `server/main.py`, `server/requirements.txt` |
| 2 | React: Vite app, WebSocket client to `ws://localhost:8765/stream`, connect on mount, display MJPEG in `<img>` with objectURL revoke, "Connecting…" / "Disconnected" text, max-width constrain, no retry | `client/` (Vite + React), `VideoStream.tsx` |
| 3 | README: How to run server and client locally | `README.md` |

---

## Tech Choices Summary (decided)

| Concern | Choice |
|--------|--------|
| Video codec | MJPEG (in-memory JPEG) |
| WS library (Python) | **websockets** (standalone) |
| React video | Blob → `URL.createObjectURL` → `<img>` |
| Server layout | Single `main.py` |
| Config | Constants at top of `main.py` |
| Clients | Single client |
| Bind | 127.0.0.1:8765 |
| Wire format | One message = one raw JPEG binary |

---

## File Checklist

- [ ] `server/requirements.txt` — opencv-python, websockets
- [ ] `server/main.py` — capture + WebSocket in one file; constants at top
- [ ] `client/` — Vite + React; `VideoStream.tsx` with WS, `<img>`, state text, revoke objectURL, max-width
- [ ] `README.md` — run server, run client (local only)

---

**Reference:** All decisions above were taken from the answered questions in `QUESTIONS.md` (video-only minimal scope, local only, no deployment, no auth).

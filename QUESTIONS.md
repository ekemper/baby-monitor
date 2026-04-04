# Implementation Questions — Video-Only Minimal Scope

**Scope:** Single path — USB webcam → Python server → WebSocket → React app. Video only. No state, no database, no users, no complex styles. **Local only: no deployment, no auth.** Questions are ordered so that answers can be integrated in implementation order.

**Decisions (simplest implementation):** Answers below assume minimal scope; local run only.

---

## Scope & Assumptions

| # | Question | Plan reference | Why it matters | Category | **Answer** |
|---|----------|----------------|----------------|----------|------------|
| S1 | Confirm: For this first version we are **not** implementing audio, auth, reconnection backoff, or deployment. Only video capture, WebSocket stream, and one React page that displays the stream. Correct? | Overall scope | Locks scope so answers to later questions don’t pull in extra features. | Scope | **Yes.** Video only; no auth; no deployment (local only). |
| S2 | Is the React app always served from the same machine as the Python server (e.g. both on your laptop, or both on the Pi), or will the browser often run on a different host (e.g. laptop browser → Pi server)? | Phase 5.1 (bind address) | Drives server bind address (localhost vs 0.0.0.0) and how the client gets the WS URL. | Technical | **Local only.** Server and browser on same machine. Bind `127.0.0.1`; client uses `ws://localhost:8765/stream`. |

---

## Phase 1 — Python: Video Capture

| # | Question | Plan reference | Why it matters | Category | **Answer** |
|---|----------|----------------|----------------|----------|------------|
| P1 | How should the camera device be selected? Hardcode index `0`, read from an env var (e.g. `CAMERA_INDEX`), or support a CLI flag? | §1.2 Video Pipeline (camera index) | Determines whether we need config/parsing or a single constant. | Technical | **Hardcode index `0`.** No env or CLI for v1. |
| P2 | What resolution and FPS should we use for the minimal version? (e.g. 640×480 @ 15 FPS, or 1280×720 @ 10 FPS?) | §1.2 (resolution, FPS) | Fixes values for OpenCV `set()`; avoids a config layer for v1. | Technical | **640×480 @ 15 FPS.** Constants at top of file. |
| P3 | If `cv2.VideoCapture.open()` fails (no camera, in use, or wrong index), what should the server do: exit with a clear message, or retry in a loop until the camera is available? | Not specified | Defines startup behavior and operator experience. | Error handling | **Exit with a clear message.** No retry loop. |
| P4 | When `cv2.read()` returns `False` or an empty/corrupt frame, should we skip that frame and continue, or retry the read once before skipping? | Not specified | Avoids sending bad frames and defines robustness of the capture loop. | Error handling | **Skip that frame and continue.** No retry. |
| P5 | When zero clients are connected, should the server keep capturing (and dropping) frames, or pause capture until at least one client connects? | §3.2 (queues, broadcast) | Tradeoff between CPU usage and “first frame” latency when a client connects. | Technical | **Keep capturing and dropping.** Simpler; first frame is ready when client connects. |

---

## Phase 1 — Python: WebSocket & Protocol

| # | Question | Plan reference | Why it matters | Category | **Answer** |
|---|----------|----------------|----------------|----------|------------|
| P6 | Do we need any HTTP endpoint (e.g. `GET /` or `GET /health`) for this minimal version, or is a WebSocket-only server acceptable? | §1.3 Endpoints | Simplifies stack (e.g. no FastAPI/aiohttp if we only need WS). | Technical | **WebSocket-only.** No HTTP endpoints. |
| P7 | Which Python WebSocket server should we use: `websockets` (standalone), or aiohttp/FastAPI (HTTP + WS)? | §1.1, Tech Summary | Affects dependencies and code shape; standalone `websockets` is minimal. | Technical | **`websockets`** (standalone). Minimal deps. |
| P8 | Confirm wire format: each WebSocket message is exactly one raw JPEG binary frame (no JSON envelope, no length header). Agree? | §1.4 Option A | Removes ambiguity for both server encode and client decode. | Technical | **Yes.** One message = one raw JPEG binary. |
| P9 | For the minimal version, should we support only one connected client at a time, or multiple clients (broadcast same frame to all)? | §1.3, §3.2 (broadcast) | Single client simplifies state and possibly allows “pause when no clients”. | Technical | **Single client.** One connection; remove when closed. |
| P10 | If the send to a client fails (e.g. client disconnected), should we catch the exception and remove that client from the list only, or also log and continue? | Not specified | Defines robustness and log noise. | Error handling | **Remove client from list; no log.** Continue. |

---

## Phase 2 — React: Connection

| # | Question | Plan reference | Why it matters | Category | **Answer** |
|---|----------|----------------|----------------|----------|------------|
| R1 | How should the React app get the WebSocket URL (e.g. `ws://host:port/stream`)? Hardcoded `ws://localhost:8765/stream`, a single build-time env var (e.g. `VITE_WS_URL`), or something else? | §4.4 config.ts | Keeps client simple while allowing different host/port (e.g. Pi IP) without code change. | Technical | **Hardcoded `ws://localhost:8765/stream`.** Local only. |
| R2 | When should the WebSocket connect? Connect as soon as the stream component mounts, with no “Start stream” button? | §4.5 Connection lifecycle | Confirms “open page → see stream” with no extra UI. | UX | **Connect on mount.** No button. |
| R3 | If the connection fails or drops, should the app reconnect at all? If yes: once, or repeatedly (with or without backoff)? For minimal scope, is “try once on mount; if fail, show a simple message and do not auto-retry” acceptable? | §4.5, Phase 6 task 6 | Keeps implementation small while defining expected behavior. | UX / Error handling | **Try once on mount; if fail, show simple message; no auto-retry.** |
| R4 | Should we show any connection state (e.g. “Connecting…”, “Disconnected”) or only the video area (and nothing when disconnected)? | §4.5, ConnectionStatus | Aligns with “no complex styles” but still gives feedback. | UX | **Show minimal state:** "Connecting…" or "Disconnected" (plain text). Video when live. |

---

## Phase 2 — React: Video Display

| # | Question | Plan reference | Why it matters | Category | **Answer** |
|---|----------|----------------|----------------|----------|------------|
| R5 | For displaying MJPEG, should we use `<img src={objectURL}>` or draw to `<canvas>`? Plan suggests both; for simplest, is `<img>` sufficient? | §4.2 Video Display | Single implementation path; canvas can be added later for mirroring/overlays. | Technical | **`<img src={objectURL}>`.** Simplest. |
| R6 | When a new JPEG blob arrives, should we revoke the previous `objectURL` immediately before assigning the new one, to avoid memory growth? | §4.2 (revoke previous) | Confirms correct lifecycle and avoids leaks. | Technical | **Yes.** Revoke previous before assigning new. |
| R7 | If a WebSocket message is received that is not a valid JPEG (e.g. empty, or wrong type), should we skip updating the image and keep the last valid frame, or show a placeholder/error state? | Not specified | Defines behavior on bad data. | Error handling | **Skip update; keep last valid frame.** No placeholder. |
| R8 | Should the video be constrained by size (e.g. max width/height or object-fit) so the page doesn’t overflow on small/large screens, or is “natural size” acceptable for the minimal version? | Not specified | Simple layout decision. | UX | **Constrain:** e.g. `max-width: 100%` so page doesn't overflow. |

---

## Edge Cases & Integration

| # | Question | Plan reference | Why it matters | Category | **Answer** |
|---|----------|----------------|----------------|----------|------------|
| E1 | Server startup order: If the React app loads before the Python server is listening, the WebSocket connection will fail. Is “user starts server, then opens app” the only supported flow for v1, or do we want the client to auto-retry connection a few times on load? | Phase 6 | Clarifies whether we need any retry logic at all for minimal scope. | UX / Error handling | **User starts server, then opens app.** No auto-retry. |
| E2 | When the browser tab is in the background, should we change behavior (e.g. pause WS, reduce FPS) or ignore and keep receiving frames as-is? | Not specified | For minimal version, “ignore” is likely acceptable. | Technical | **Ignore.** Keep receiving as-is. |
| E3 | If the client is slow and the server’s send queue backs up, the plan suggests a bounded queue (e.g. maxsize 2–3) and drop frames. Confirm: we drop oldest frames and always send the latest? | §3.2 | Confirms backpressure strategy. | Technical | **Yes.** Bounded queue (e.g. maxsize 2); drop oldest; send latest. |
| E4 | Port and path: Use a single fixed port (e.g. 8765) and path `/stream` for both server and client, or make one of them configurable even in the minimal version? | §3.3, §4.4 | Keeps config surface minimal. | Technical | **Fixed:** port 8765, path `/stream`. Both sides. |

---

## Optional: Structure & Config

| # | Question | Plan reference | Why it matters | Category | **Answer** |
|---|----------|----------------|----------------|----------|------------|
| O1 | For the minimal version, is a single `main.py` (capture loop + WebSocket in one file) acceptable, or do we want the planned split (e.g. `capture/video.py`, `stream/ws_handler.py`) from the start? | §3.1 Suggested layout | Tradeoff between “simplest file layout” and “structure that matches the plan”. | Technical | **Single `main.py`.** Capture + WebSocket in one file. |
| O2 | Should camera index, resolution, FPS, and port live in a `config.py` (or env) even for v1, or as constants at the top of `main.py`? | §3.3 Configuration | Reduces moving parts if we use constants; makes tuning easier if we use config. | Technical | **Constants at top of `main.py`.** No config file or env. |

---

**Decisions summary:** Local only, no deployment, no auth. Python: one file (`main.py`), camera index 0, 640×480 @ 15 FPS, WebSocket-only on 127.0.0.1:8765/stream, raw JPEG, single client. React: hardcoded `ws://localhost:8765/stream`, connect on mount, no retry, minimal connection text ("Connecting…" / "Disconnected"), `<img>` + revoke objectURL, max-width constrain. Fixed port 8765 and path `/stream`.

**Next step:** Integrate these answers into the implementation plan and implement.

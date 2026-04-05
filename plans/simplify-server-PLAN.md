# Simplify Server — Drop OpenCV, Drop React Client

## Summary / goal

Replace the heavyweight OpenCV dependency (250 apt packages, 601MB) with a lightweight `ffmpeg` subprocess that pipes MJPEG frames from the USB webcam. Remove the React web client entirely since the iOS app is the only viewer. The result: the server runs on a fresh Raspberry Pi with just 3 small pip packages and system `ffmpeg`.

## Scope

**In scope:**

1. Replace OpenCV camera capture with `ffmpeg` subprocess piping MJPEG to stdout
2. Remove all React client serving code from the server
3. Remove `opencv-python` from Python dependencies
4. Delete the `client/` directory entirely
5. Simplify `deploy.sh` — no npm build step, no client dist commit
6. Update `README.md` to reflect the simplified Pi-only, iOS-only system
7. Update `.gitignore` to remove client-related entries
8. Update `deploy.sh` to install `ffmpeg` via apt if missing

**Out of scope:**

- iOS app changes (the WebSocket protocol is unchanged — binary JPEG frames)
- ngrok integration (unchanged)
- Multi-viewer support (unchanged)
- Health endpoint (unchanged)

**Dependencies:**

- `ffmpeg` must be installed on the Pi (`sudo apt install ffmpeg` — likely already present)
- USB webcam must support MJPEG output (virtually all modern USB webcams do; ffmpeg falls back to software encoding if not)

## Approach

Single phase — this is a contained refactor. All changes are server-side and the WebSocket protocol (binary JPEG frames) does not change, so the iOS app works without modification.

### Steps

1. Rewrite `server/main.py` capture logic
2. Update `server/requirements.txt`
3. Delete `client/` directory
4. Rewrite `deploy.sh`
5. Rewrite `README.md`
6. Clean up `.gitignore`
7. Delete stale `.env-example`

## Technical implementation detail

### 1. Layout (after)

```
server/
  main.py              (MOD — ffmpeg capture, no static serving)
  requirements.txt     (MOD — remove opencv-python)
  .env                 (no change)
  .env.example         (no change)
deploy.sh              (MOD — simplified)
README.md              (MOD — simplified)
.gitignore             (MOD — remove client entries)
ios/                   (no change)
plans/                 (no change)
```

### 2. ffmpeg capture design

Replace the OpenCV `capture_loop` with an ffmpeg subprocess:

```python
import subprocess
import shutil

FFMPEG = shutil.which("ffmpeg")
DEVICE = "/dev/video0"
WIDTH = 640
HEIGHT = 480
FPS = 15

def capture_loop(frame_queue: queue.Queue[bytes]) -> None:
    if not FFMPEG:
        log.error("ffmpeg not found. Install with: sudo apt install ffmpeg")
        sys.exit(1)

    cmd = [
        FFMPEG,
        "-f", "v4l2",
        "-input_format", "mjpeg",
        "-video_size", f"{WIDTH}x{HEIGHT}",
        "-framerate", str(FPS),
        "-i", DEVICE,
        "-c:v", "copy",        # passthrough, no re-encoding
        "-f", "image2pipe",
        "-vcodec", "mjpeg",
        "-"
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    buf = bytearray()
    SOI = b"\xff\xd8"
    EOI = b"\xff\xd9"

    while True:
        chunk = proc.stdout.read(4096)
        if not chunk:
            log.error("ffmpeg process exited")
            break
        buf.extend(chunk)
        while True:
            soi = buf.find(SOI)
            if soi == -1:
                break
            eoi = buf.find(EOI, soi + 2)
            if eoi == -1:
                break
            frame = bytes(buf[soi:eoi + 2])
            buf = buf[eoi + 2:]
            # drop-if-full, same as current behavior
            try:
                frame_queue.put(frame, block=False)
            except queue.Full:
                try:
                    frame_queue.get_nowait()
                except queue.Empty:
                    pass
                try:
                    frame_queue.put(frame, block=False)
                except queue.Full:
                    pass
```

Key design decisions:
- **`-input_format mjpeg`**: requests hardware MJPEG from the webcam (near-zero CPU). Falls back to raw capture + software encode if the camera doesn't support it.
- **`-c:v copy`**: passthrough, no re-encoding.
- **SOI/EOI parsing**: splits the MJPEG bytestream into individual JPEG frames. This is standard and reliable — every JPEG starts with `\xff\xd8` and ends with `\xff\xd9`.
- **Same queue interface**: `broadcast_loop` and the rest of the server are unchanged.

### 3. Server cleanup

Remove from `create_app`:
- All `STATIC_DIR` references
- `index_handler`
- All static file routes (`/`, `/assets`, `/vite.svg`)

The server only exposes:
- `GET /health` — JSON health check
- `WS /stream` — WebSocket JPEG stream

### 4. Deploy script

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_PASSWORD="$(grep '^PI_PASSWORD=' "$SCRIPT_DIR/server/.env" | cut -d= -f2-)"
# ... same PI config ...

# Push & pull
git push
run_ssh "cd ${PI_DIR} && git pull"

# Ensure ffmpeg is installed
run_ssh "which ffmpeg || sudo apt install -y ffmpeg"

# Install Python deps (no opencv!)
run_ssh "TMPDIR=/var/tmp pip3 install --break-system-packages --no-cache-dir -q -r ${PI_DIR}/server/requirements.txt"
```

No more npm build, no more client dist commit. Uses `TMPDIR=/var/tmp` and `--no-cache-dir` to avoid the 214MB tmpfs issue on Pi.

### 5. Data flow (unchanged)

```
USB webcam → ffmpeg (MJPEG passthrough) → stdout pipe
    → Python capture_loop → frame_queue
    → broadcast_loop → WebSocket → iOS app
```

The WebSocket protocol is identical: each message is a raw JPEG binary blob. The iOS app's `WebSocketManager` works without changes.

## Risks & mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| USB webcam doesn't support hardware MJPEG | Low (most do) | ffmpeg auto-falls back to raw capture + software encode. Log a warning. |
| ffmpeg not installed on Pi | Low (usually pre-installed) | Deploy script installs it. Startup check with clear error. |
| JPEG SOI/EOI parsing edge case | Very low | SOI/EOI markers are guaranteed by the JPEG spec. The pattern is widely used. |

## Open decisions

All decisions resolved during design:
- **Camera type:** USB webcam → use ffmpeg with V4L2
- **No Mac dev support:** Pi-only, no OpenCV fallback
- **No React client:** iOS-only, delete client/ entirely
- **Frame splitting:** SOI/EOI marker parsing from ffmpeg image2pipe output

## Deliverables Manifest

1. MOD  `server/main.py` — Replace OpenCV capture_loop with ffmpeg subprocess (SOI/EOI frame splitting); remove all STATIC_DIR, index_handler, and static file serving code; remove `import cv2`; add `import subprocess, shutil`; add startup check for ffmpeg binary
2. MOD  `server/requirements.txt` — Remove `opencv-python>=4.8.0` (keep aiohttp, pyngrok, python-dotenv)
3. DELETE  `client/` — Remove entire React client directory (client/src, client/dist, client/package.json, etc.)
4. MOD  `deploy.sh` — Remove npm build and client dist commit steps; add `which ffmpeg || sudo apt install -y ffmpeg`; use `TMPDIR=/var/tmp --no-cache-dir` for pip; remove sshpass install (assume pre-installed from prior run)
5. MOD  `README.md` — Rewrite for Pi-only + iOS-only: remove Node.js prerequisite, remove React client sections, remove `/` endpoint from API table, add ffmpeg prerequisite, document deploy.sh usage
6. MOD  `.gitignore` — Remove `client/node_modules/`, `!client/dist/`, and React-related entries
7. DELETE  `server/.env-example` — Stale duplicate; `server/.env.example` is the canonical file

**Implementation protocol:** The implementing agent must follow the `plan-implementation` cursor rule when executing this plan.

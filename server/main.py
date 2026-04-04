"""
Video-only WebSocket stream from USB webcam.
Serves static (React build) + WebSocket on one port for ngrok. Local: 127.0.0.1:8765.
"""
import asyncio
import logging
import os
import queue
import sys
import threading
from typing import Any, Optional

import cv2
from aiohttp import web

# --- Constants (no config file) ---
CAMERA_INDEX = 0
WIDTH = 640
HEIGHT = 480
FPS = 15
HOST = "127.0.0.1"
PORT = 8765

FRAME_QUEUE_MAXSIZE = 2

# Static files (React build) for ngrok; relative to this file.
SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(SERVER_DIR, "..", "client", "dist")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# Shared: current WebSocket client (single client). Only main thread touches this.
current_client: Optional[Any] = None


def capture_loop(frame_queue: queue.Queue[bytes]) -> None:
    """Run in thread: read from camera, encode MJPEG, put in queue (drop oldest if full)."""
    cap = cv2.VideoCapture(CAMERA_INDEX)
    if not cap.isOpened():
        log.error("Could not open camera (index %d). Is it in use or disconnected?", CAMERA_INDEX)
        sys.exit(1)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, FPS)
    log.info("Capture started: camera %d, %dx%d @ %d FPS", CAMERA_INDEX, WIDTH, HEIGHT, FPS)

    while True:
        ret, frame = cap.read()
        if not ret or frame is None:
            continue
        ok, buf = cv2.imencode(".jpg", frame)
        if not ok or buf is None:
            continue
        jpeg = buf.tobytes()
        try:
            frame_queue.put(jpeg, block=False)
        except queue.Full:
            try:
                frame_queue.get_nowait()
            except queue.Empty:
                pass
            try:
                frame_queue.put(jpeg, block=False)
            except queue.Full:
                pass


async def send_loop(ws: web.WebSocketResponse, frame_queue: queue.Queue[bytes]) -> None:
    """Pull frames from queue and send to client. Stops on disconnect or send error."""
    loop = asyncio.get_event_loop()
    while True:
        frame = await loop.run_in_executor(None, frame_queue.get)
        if current_client is not ws:
            break
        try:
            await ws.send_bytes(frame)
        except Exception:
            break


async def stream_handler(request: web.Request) -> web.StreamResponse:
    """WebSocket at /stream: single client, raw JPEG frames."""
    global current_client
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    if current_client is not None:
        log.info("Replacing existing client")
        await current_client.close()
    current_client = ws
    log.info("Client connected")

    try:
        frame_queue = request.app["frame_queue"]
        await send_loop(ws, frame_queue)
    finally:
        if current_client is ws:
            current_client = None
            log.info("Client disconnected")
    return ws


async def index_handler(_request: web.Request) -> web.FileResponse:
    """Serve React index.html for ngrok (same origin as /stream)."""
    return web.FileResponse(os.path.join(STATIC_DIR, "index.html"))


def create_app(frame_queue: queue.Queue[bytes]) -> web.Application:
    app = web.Application()
    app["frame_queue"] = frame_queue

    # WebSocket first so /stream is exact
    app.router.add_get("/stream", stream_handler)

    if os.path.isdir(STATIC_DIR):
        app.router.add_get("/", index_handler)
        assets_path = os.path.join(STATIC_DIR, "assets")
        if os.path.isdir(assets_path):
            app.router.add_static("/assets", assets_path, name="assets")
        favicon = os.path.join(STATIC_DIR, "vite.svg")
        if os.path.isfile(favicon):
            app.router.add_get("/vite.svg", lambda r: web.FileResponse(favicon))
        log.info("Serving static from %s (for ngrok)", STATIC_DIR)
    else:
        async def no_static(_: web.Request) -> web.Response:
            return web.Response(
                text="Static not found. Run: cd client && npm run build",
                content_type="text/plain",
                status=404,
            )
        app.router.add_get("/", no_static)

    return app


async def main() -> None:
    frame_queue: queue.Queue[bytes] = queue.Queue(maxsize=FRAME_QUEUE_MAXSIZE)
    t = threading.Thread(target=capture_loop, args=(frame_queue,), daemon=True)
    t.start()

    app = create_app(frame_queue)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, HOST, PORT)
    await site.start()

    log.info("Server listening on http://%s:%s", HOST, PORT)
    log.info("WebSocket at ws://%s:%s/stream", HOST, PORT)
    if os.path.isdir(STATIC_DIR):
        log.info("Static app served at / (use with ngrok for remote access)")
    await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())

"""
Video-only WebSocket stream from USB webcam.
Supports multiple concurrent viewers. Serves static (React build) + WebSocket
on one port. Optional integrated ngrok tunnel via .env config.
"""
import asyncio
import json
import logging
import os
import queue
import sys
import threading
import time
from typing import Optional

import cv2
from aiohttp import web
from dotenv import load_dotenv

# --- Constants ---
CAMERA_INDEX = 0
WIDTH = 640
HEIGHT = 480
FPS = 15
HOST = "127.0.0.1"
PORT = 8765

FRAME_QUEUE_MAXSIZE = 2

SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(SERVER_DIR, "..", "client", "dist")

load_dotenv(dotenv_path=os.path.join(SERVER_DIR, ".env"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

connected_clients: set[web.WebSocketResponse] = set()
server_start_time: float = 0.0


def capture_loop(frame_queue: queue.Queue[bytes]) -> None:
    """Run in thread: read from camera, encode JPEG, put in queue (drop oldest if full)."""
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


async def broadcast_loop(app: web.Application) -> None:
    """Pull frames from queue and broadcast to all connected clients."""
    frame_queue: queue.Queue[bytes] = app["frame_queue"]
    loop = asyncio.get_event_loop()
    while True:
        frame = await loop.run_in_executor(None, frame_queue.get)
        if not connected_clients:
            continue
        dead: list[web.WebSocketResponse] = []
        for ws in connected_clients:
            try:
                await ws.send_bytes(frame)
            except Exception:
                dead.append(ws)
        for ws in dead:
            connected_clients.discard(ws)
            log.info("Removed dead client (%d viewers)", len(connected_clients))


async def start_broadcast(app: web.Application) -> None:
    app["broadcast_task"] = asyncio.create_task(broadcast_loop(app))


async def stop_broadcast(app: web.Application) -> None:
    app["broadcast_task"].cancel()
    try:
        await app["broadcast_task"]
    except asyncio.CancelledError:
        pass


async def stream_handler(request: web.Request) -> web.StreamResponse:
    """WebSocket at /stream: multiple concurrent viewers, raw JPEG frames."""
    ws = web.WebSocketResponse(heartbeat=20.0)
    await ws.prepare(request)

    connected_clients.add(ws)
    log.info("Client connected (%d viewers)", len(connected_clients))

    try:
        async for _msg in ws:
            pass
    finally:
        connected_clients.discard(ws)
        log.info("Client disconnected (%d viewers)", len(connected_clients))
    return ws


async def health_handler(_request: web.Request) -> web.Response:
    """GET /health — JSON health check with viewer count and uptime."""
    return web.Response(
        text=json.dumps({
            "status": "ok",
            "viewers": len(connected_clients),
            "uptime_seconds": round(time.time() - server_start_time, 1),
        }),
        content_type="application/json",
    )


async def index_handler(_request: web.Request) -> web.FileResponse:
    """Serve React index.html for ngrok (same origin as /stream)."""
    return web.FileResponse(os.path.join(STATIC_DIR, "index.html"))


def setup_ngrok() -> Optional[str]:
    """Start ngrok tunnel if NGROK_AUTHTOKEN and NGROK_DOMAIN are set. Returns public URL or None."""
    authtoken = os.environ.get("NGROK_AUTHTOKEN")
    domain = os.environ.get("NGROK_DOMAIN")

    if not authtoken or not domain:
        log.info("ngrok not configured — running in local-only mode")
        return None

    try:
        from pyngrok import ngrok
        ngrok.set_auth_token(authtoken)
        tunnel = ngrok.connect(addr=str(PORT), proto="http", hostname=domain)
        log.info("ngrok tunnel active: %s", tunnel.public_url)
        return tunnel.public_url
    except Exception as exc:
        log.error("Failed to start ngrok tunnel: %s", exc)
        return None


def teardown_ngrok(public_url: Optional[str]) -> None:
    """Disconnect ngrok tunnel and kill the process."""
    if public_url is None:
        return
    try:
        from pyngrok import ngrok
        ngrok.disconnect(public_url)
        ngrok.kill()
        log.info("ngrok tunnel closed")
    except Exception:
        pass


def create_app(frame_queue: queue.Queue[bytes]) -> web.Application:
    app = web.Application()
    app["frame_queue"] = frame_queue
    app["public_url"] = None

    app.on_startup.append(start_broadcast)
    app.on_cleanup.append(stop_broadcast)

    app.router.add_get("/stream", stream_handler)
    app.router.add_get("/health", health_handler)

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
    global server_start_time
    server_start_time = time.time()

    frame_queue: queue.Queue[bytes] = queue.Queue(maxsize=FRAME_QUEUE_MAXSIZE)
    t = threading.Thread(target=capture_loop, args=(frame_queue,), daemon=True)
    t.start()

    public_url = setup_ngrok()

    app = create_app(frame_queue)
    app["public_url"] = public_url
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, HOST, PORT)
    await site.start()

    log.info("Server listening on http://%s:%s", HOST, PORT)
    log.info("WebSocket at ws://%s:%s/stream", HOST, PORT)
    if os.path.isdir(STATIC_DIR):
        log.info("Static app served at / (use with ngrok for remote access)")

    try:
        await asyncio.Future()
    finally:
        teardown_ngrok(public_url)


if __name__ == "__main__":
    asyncio.run(main())

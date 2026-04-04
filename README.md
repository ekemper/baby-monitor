# Baby Monitor (video-only)

USB webcam → Python server → WebSocket → React app. Video only. Works locally and over the internet via ngrok (no auth).

## Prerequisites

- Python 3.9+
- Node.js 18+
- USB webcam (default camera index 0)
- [ngrok](https://ngrok.com/download) (for remote access)

## Run locally

### 1. Start the Python server

```bash
cd server
pip install -r requirements.txt
python main.py
```

Server binds to `127.0.0.1:8765`. WebSocket at `ws://127.0.0.1:8765/stream`.

### 2. Start the React app (dev)

In a second terminal:

```bash
cd client
npm install
npm run dev
```

Open the URL shown (e.g. http://localhost:5173). The app connects to `ws://localhost:8765/stream` and displays the stream.

**Order:** Start the server first, then open the React app. If the server is not running, the app shows "Disconnected" (no auto-retry).

---

## Run with ngrok (remote access)

One URL serves both the app and the stream. Use this when you want to view the stream from another network (e.g. phone, another house).

### 1. Build the React app

```bash
cd client
npm install
npm run build
```

This creates `client/dist/`.

### 2. Start the Python server

From the repo root:

```bash
cd server
pip install -r requirements.txt
python main.py
```

You should see: `Serving static from .../client/dist (for ngrok)` and `Server listening on http://127.0.0.1:8765`. The server now serves the built app at `/` and the WebSocket at `/stream`.

### 3. Expose with ngrok

In another terminal:

```bash
ngrok http 8765
```

ngrok will print a public URL, e.g. `https://abc123.ngrok-free.app`.

### 4. Open the ngrok URL

Open that URL in a browser (on any device). The page loads the app and connects to the stream over the same host (`wss://...ngrok.../stream`). No extra config.

**Note:** If you don’t build the client first, the server still runs and WebSocket works, but `GET /` returns "Static not found". Use local dev (above) or run `npm run build` in `client` for ngrok.

---

## Config (server)

Constants are at the top of `server/main.py`: camera index `0`, 640×480 @ 15 FPS, port 8765.

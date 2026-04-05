# Baby Monitor (video-only)

USB webcam → Python server → WebSocket → React app or iOS app. Video only. Supports multiple simultaneous viewers. Works locally and over the internet via integrated ngrok tunnel.

## Prerequisites

- Python 3.9+
- Node.js 18+ (for the React client)
- USB webcam (default camera index 0)
- [ngrok account](https://ngrok.com/) with a free static domain (for remote access)

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

Multiple browser tabs can view the stream simultaneously.

---

## Run with ngrok (remote access)

The server manages the ngrok tunnel automatically — no separate `ngrok` command needed.

### 1. Configure ngrok credentials

```bash
cp server/.env.example server/.env
```

Edit `server/.env` with your ngrok auth token and reserved domain:

```
NGROK_AUTHTOKEN=your-token-here
NGROK_DOMAIN=your-domain.ngrok-free.dev
```

Get your auth token at [dashboard.ngrok.com/get-started/your-authtoken](https://dashboard.ngrok.com/get-started/your-authtoken). Claim a free static domain at [dashboard.ngrok.com/domains](https://dashboard.ngrok.com/domains).

### 2. Build the React app

```bash
cd client
npm install
npm run build
```

This creates `client/dist/`.

### 3. Start the server

```bash
cd server
pip install -r requirements.txt
python main.py
```

The server starts the ngrok tunnel automatically and logs the public URL. Open that URL in any browser to view the stream remotely.

If `.env` is missing or empty, the server runs in local-only mode (no tunnel).

---

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/stream` | WebSocket | Binary JPEG frames, one per message. Connect multiple clients simultaneously. |
| `/health` | GET | JSON health check: `{"status": "ok", "viewers": N, "uptime_seconds": N}` |
| `/` | GET | Serves the built React app (from `client/dist/`) |

## Config (server)

Constants are at the top of `server/main.py`: camera index `0`, 640×480 @ 15 FPS, port 8765.

Environment variables (in `server/.env`):

| Variable | Description |
|----------|-------------|
| `NGROK_AUTHTOKEN` | ngrok auth token (required for remote access) |
| `NGROK_DOMAIN` | ngrok reserved domain (required for remote access) |

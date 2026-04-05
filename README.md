# Baby Monitor

USB webcam → ffmpeg → Python server → WebSocket → iOS app. Video only, multiple simultaneous viewers, remote access via ngrok.

## Prerequisites

- Raspberry Pi with Raspberry Pi OS
- USB webcam
- `ffmpeg` (`sudo apt install ffmpeg`)
- Python 3.9+
- [ngrok account](https://ngrok.com/) with a free static domain (for remote access)

## Setup

### 1. Clone and configure

```bash
git clone <repo-url> ~/baby-monitor
cd ~/baby-monitor/server
cp .env.example .env
```

Edit `server/.env` with your ngrok credentials:

```
NGROK_AUTHTOKEN=your-token-here
NGROK_DOMAIN=your-domain.ngrok-free.dev
```

Get your auth token at [dashboard.ngrok.com/get-started/your-authtoken](https://dashboard.ngrok.com/get-started/your-authtoken). Claim a free static domain at [dashboard.ngrok.com/domains](https://dashboard.ngrok.com/domains).

### 2. Install dependencies

```bash
sudo apt install -y ffmpeg
pip3 install --break-system-packages -r server/requirements.txt
```

### 3. Start the server

```bash
cd server
python3 main.py
```

The server captures from the USB webcam via ffmpeg, starts the ngrok tunnel, and serves the video stream over WebSocket. If `.env` is missing or empty, it runs in local-only mode.

## Deploy from Mac

The `deploy.sh` script pushes code to the Pi over git:

```bash
./deploy.sh
```

It pushes to origin, pulls on the Pi, ensures ffmpeg is installed, installs Python deps, and syncs the `.env` file. Requires `sshpass` (auto-installed on first run via `brew install hudochenkov/sshpass/sshpass`).

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/stream` | WebSocket | Binary JPEG frames, one per message. Multiple concurrent viewers. |
| `/health` | GET | `{"status": "ok", "viewers": N, "uptime_seconds": N}` |

## Config

Constants at the top of `server/main.py`:

| Setting | Default | Description |
|---------|---------|-------------|
| `DEVICE` | `/dev/video0` | V4L2 device path |
| `WIDTH` | `640` | Capture width |
| `HEIGHT` | `480` | Capture height |
| `FPS` | `15` | Capture framerate |
| `PORT` | `8765` | Server port |

Environment variables (in `server/.env`):

| Variable | Description |
|----------|-------------|
| `NGROK_AUTHTOKEN` | ngrok auth token (required for remote access) |
| `NGROK_DOMAIN` | ngrok reserved domain (required for remote access) |
| `PI_PASSWORD` | Pi SSH password (used by `deploy.sh`) |

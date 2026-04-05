# iOS Viewer App — Master Plan

## Summary / goal

Build a native SwiftUI iPhone app that serves as a viewer for the baby monitor, connecting to the existing Python/aiohttp server over WebSocket to display the JPEG video stream. The server URL (`wss://subglobous-pawky-mark.ngrok-free.dev/stream`) is hardcoded in the app. Alongside the app, enhance the server with multi-viewer support, integrated ngrok tunneling, a health-check endpoint, and WebSocket ping/pong keepalive.

## Scope

**In scope:**

1. Server: multi-viewer WebSocket support (concurrent clients)
2. Server: integrated pyngrok tunnel with reserved domain (`NGROK_DOMAIN` env var)
3. Server: `GET /health` endpoint
4. Server: WebSocket ping/pong keepalive
5. iOS: SwiftUI app (iOS 17+) with `URLSessionWebSocketTask` for binary JPEG streaming
6. iOS: hardcoded server URL — app connects on launch, no server discovery UI
7. iOS: fullscreen mode, landscape support, auto-reconnect with exponential backoff
8. iOS: night mode (amber overlay + brightness reduction)
9. iOS: background keep-alive and local disconnect notifications

**Out of scope:**

- Audio / two-way communication
- Android app
- User authentication or encryption beyond ngrok's TLS
- Remote push notifications (APNs server infrastructure)
- App Store distribution (TestFlight / ad-hoc only)
- Recording or playback
- Multiple cameras
- QR code scanning / server discovery UI
- Dynamic server list / multiple server management

**Dependencies:**

- Python 3.9+ and the existing `server/main.py` codebase
- Xcode 15+ on macOS for iOS development
- `xcodegen` (installed via `brew install xcodegen`) for Xcode project generation
- ngrok account with a reserved domain and auth token
- Physical iPhone or simulator running iOS 17+

## Approach

Four phases, with Phases 1 and 2 parallelizable. Each phase is independently testable.

**Phase 1 — Server enhancements** (see [ios-viewer-phase-1-IMPL.md](ios-viewer-phase-1-IMPL.md))
Modify `server/main.py` to support multiple concurrent viewers, add `/health` endpoint, integrate pyngrok for automatic tunnel startup, and add WebSocket ping/pong. After this phase the existing React client still works and multiple browsers can view simultaneously.

**Phase 2 — Core iOS app** (see [ios-viewer-phase-2-IMPL.md](ios-viewer-phase-2-IMPL.md))
Create the SwiftUI app with hardcoded server URL, WebSocket video streaming, and connection status. The app launches straight to the stream view. After this phase the iPhone can display the baby monitor stream.

**Phase 3 — Enhanced UX** (see [ios-viewer-phase-3-IMPL.md](ios-viewer-phase-3-IMPL.md))
Add fullscreen mode, landscape layout, auto-reconnect with backoff, and night mode overlay. After this phase the app is comfortable for daily use.

**Phase 4 — Background & notifications** (see [ios-viewer-phase-4-IMPL.md](ios-viewer-phase-4-IMPL.md))
Add background WebSocket monitoring via `BGTaskScheduler` and local notifications when the connection drops while the app is backgrounded. After this phase the app alerts the parent if the baby monitor goes offline.

## Technical implementation detail

Detailed specs live in the phase implementation docs. High-level architecture:

### Layout

```
server/
  main.py              (MOD — multi-viewer, /health, pyngrok, ping/pong)
  requirements.txt     (MOD — add pyngrok, python-dotenv)
  .env.example         (NEW — template for NGROK_AUTHTOKEN, NGROK_DOMAIN)

ios/
  project.yml          (NEW — XcodeGen spec)
  BabyMonitor/
    BabyMonitorApp.swift
    Config.swift
    Services/
      WebSocketManager.swift
      BackgroundMonitor.swift
      NotificationManager.swift
    Views/
      ContentView.swift
      StreamView.swift
      NightModeOverlay.swift
    Storage/
      PreferencesStorage.swift
    Assets.xcassets/
```

### Data and APIs

- **WebSocket protocol (unchanged):** `ws(s)://<host>/stream` — server sends binary frames, each frame is a complete JPEG image. No handshake beyond the WebSocket upgrade.
- **`GET /health`** — returns `{"status": "ok", "viewers": N, "uptime_seconds": N}` with status 200.

### Data flow

1. User opens iOS app → app immediately connects to hardcoded WebSocket URL
2. App calls `GET /health` to verify reachability, then opens WebSocket to `/stream`
3. Receives binary JPEG frames → decodes to `UIImage` → displays in SwiftUI `Image`
4. On disconnect → auto-reconnect with backoff (Phase 3) or local notification (Phase 4 if backgrounded)

### Integrations

- **pyngrok:** Python library that wraps the ngrok agent binary. Server calls `ngrok.set_auth_token()` and `ngrok.connect()` on startup. Reads `NGROK_AUTHTOKEN` and `NGROK_DOMAIN` from `.env` via `python-dotenv`.
- **URLSession (iOS):** WebSocket via `URLSessionWebSocketTask`; HTTP health check via `URLSession.shared.data(from:)`.
- **BGTaskScheduler (iOS):** Background refresh task registered with identifier `com.babymonitor.connectionCheck`.
- **UNUserNotificationCenter (iOS):** Local notifications for disconnect alerts.

## Risks & mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **pyngrok binary compatibility** — pyngrok downloads the ngrok binary; may fail on some systems or in CI | Server won't start with ngrok | Make ngrok optional: server runs locally without it. Only fail if `--ngrok` flag is passed and tunnel can't start. |
| **iOS background execution limits** — BGTaskScheduler gives ~30s of execution with no guaranteed schedule | Disconnect notification may be delayed minutes | Document this limitation. The notification is best-effort, not real-time. For reliable monitoring, keep the app in foreground. |
| **WebSocket over cellular** — high latency and bandwidth consumption streaming JPEG at 15fps over LTE | Poor experience on cellular | Already mitigated by 640x480 resolution. Could add JPEG quality reduction in future (out of scope). |
| **Single server, no auth** — anyone with the ngrok URL can view the stream | Privacy risk | Out of scope for this plan. Mitigate by keeping the ngrok URL private. Auth can be added later. |
| **Hardcoded URL** — changing the ngrok domain requires a code change and rebuild | Inflexible | Acceptable for a personal baby monitor. If the domain changes, update `Config.swift` and rebuild. |
| **Xcode project generation** — xcodegen must produce a valid project; manual project.pbxproj is fragile | Build failures | Use xcodegen (battle-tested tool) rather than hand-writing the project file. |

## Open decisions

All decisions resolved during design. See approach for rationale:
- Framework: SwiftUI (native, best performance, iOS 17+ for @Observable)
- WebSocket: URLSessionWebSocketTask (Apple-native, supports background sessions)
- Notifications: local only (no APNs server needed)
- ngrok: integrated via pyngrok with reserved domain
- Project generation: xcodegen from project.yml
- Server URL: hardcoded in `Config.swift` (no dynamic discovery)

## Dependency graph

### Interface contracts (defined before parallel work begins)

- **WebSocket stream protocol:** `ws(s)://<host>/stream` sends binary WebSocket frames, each a complete JPEG image. No application-level framing. Already implemented and unchanged.
- **Health API:** `GET /health` → `200 OK` with body `{"status": "ok", "viewers": <int>, "uptime_seconds": <float>}`. Content-Type: `application/json`.

### Phases 1 + 2 — Foundation (parallelizable)

**Phase 1: Server enhancements** [sub-agent: generalPurpose]
- Items 1–5 from manifest
- Depends on: none
- Produces: multi-viewer WebSocket, /health, pyngrok integration

**Phase 2: Core iOS app** [sub-agent: generalPurpose]
- Items 6–13 from manifest
- Depends on: WebSocket stream protocol (already exists), Health API contract (shape only)
- Produces: working iOS viewer app

**Sync point:** Both phases complete → verify iOS app connects to enhanced server → proceed

### Phase 3 — Enhanced UX (sequential)
- Items 14–18 from manifest
- Depends on: Phase 2 complete (iOS app exists)
- Produces: polished daily-use experience

### Phase 4 — Background & notifications (sequential)
- Items 19–23 from manifest
- Depends on: Phase 2 complete (WebSocketManager exists)
- Produces: background monitoring + disconnect alerts

## Deliverables Manifest

### Phase 1 — Server enhancements

1. MOD  `server/main.py` — Replace single-client with multi-viewer set, add /health endpoint, integrate pyngrok tunnel, add WebSocket ping/pong keepalive
2. MOD  `server/requirements.txt` — Add pyngrok, python-dotenv
3. NEW  `server/.env.example` — Template with NGROK_AUTHTOKEN and NGROK_DOMAIN placeholders
4. MOD  `.gitignore` — Add `server/.env` to ignore list
5. MOD  `README.md` — Update run instructions for integrated ngrok, .env setup, /health endpoint, multi-viewer

### Phase 2 — Core iOS app

6.  NEW  `ios/project.yml` — XcodeGen project spec: iOS 17+ deployment target, SwiftUI lifecycle, bundle ID com.babymonitor.viewer, iPhone only
7.  NEW  `ios/BabyMonitor/BabyMonitorApp.swift` — @main app entry point with WindowGroup
8.  NEW  `ios/BabyMonitor/Config.swift` — Hardcoded constants: `serverURL` ("wss://subglobous-pawky-mark.ngrok-free.dev/stream"), `healthURL` ("https://subglobous-pawky-mark.ngrok-free.dev/health"), `serverName` ("Baby Monitor")
9.  NEW  `ios/BabyMonitor/Services/WebSocketManager.swift` — @Observable class wrapping URLSessionWebSocketTask; receives binary JPEG frames, decodes to UIImage, exposes published image and connection state
10. NEW  `ios/BabyMonitor/Views/ContentView.swift` — Root view that directly presents StreamView
11. NEW  `ios/BabyMonitor/Views/StreamView.swift` — Black background, displays decoded JPEG frames as SwiftUI Image with aspect-fit, connection status overlay (connecting/live/disconnected)
12. NEW  `ios/BabyMonitor/Assets.xcassets/Contents.json` — Asset catalog root JSON
13. NEW  `ios/BabyMonitor/Assets.xcassets/AppIcon.appiconset/Contents.json` — App icon placeholder configuration (empty icon set)

### Phase 3 — Enhanced UX

14. MOD  `ios/BabyMonitor/Views/StreamView.swift` — Fullscreen toggle on tap (hide status bar, home indicator), landscape adaptive layout with aspect-fit scaling, night mode toggle button in toolbar
15. MOD  `ios/BabyMonitor/Services/WebSocketManager.swift` — Auto-reconnect with exponential backoff: 1s → 2s → 4s → 8s → 16s → 30s cap; reset on successful connection
16. NEW  `ios/BabyMonitor/Views/NightModeOverlay.swift` — Semi-transparent amber Color overlay + screen brightness reduction; passes through touches
17. MOD  `ios/BabyMonitor/Views/ContentView.swift` — Night mode @State, conditionally overlay NightModeOverlay, manage UIScreen brightness
18. NEW  `ios/BabyMonitor/Storage/PreferencesStorage.swift` — UserDefaults-backed persistence for night mode on/off preference

### Phase 4 — Background & notifications

19. MOD  `ios/BabyMonitor/BabyMonitorApp.swift` — Register BGAppRefreshTask with identifier, handle scenePhase changes (.background triggers task scheduling)
20. NEW  `ios/BabyMonitor/Services/BackgroundMonitor.swift` — BGTaskScheduler wrapper: schedule periodic health checks using hardcoded health URL from Config, determine if server is reachable
21. NEW  `ios/BabyMonitor/Services/NotificationManager.swift` — UNUserNotificationCenter wrapper: request permission on first launch, post local notification on disconnect with server name from Config
22. MOD  `ios/BabyMonitor/Services/WebSocketManager.swift` — On disconnect, call NotificationManager if app is backgrounded; expose isBackgrounded flag
23. MOD  `ios/project.yml` — Add BGTaskSchedulerPermittedIdentifiers (com.babymonitor.connectionCheck) to Info.plist settings

**Implementation protocol:** The implementing agent must follow the `plan-implementation` cursor rule when executing this plan.

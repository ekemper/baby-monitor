# iOS Viewer App — Phase 2: Core iOS App

**Master plan:** [ios-viewer-PLAN.md](ios-viewer-PLAN.md)
**Phase:** 2 of 4
**Prerequisites:** None — this phase can run in parallel with Phase 1. The iOS app connects to the existing WebSocket server which already sends binary JPEG frames. The `/health` endpoint (Phase 1) is used if available but the app degrades gracefully if it doesn't exist yet.
**Parallel tracks:** No — sequential
**Estimated scope:** medium

## Summary

Create a native SwiftUI iPhone app that connects to the baby monitor server over WebSocket and displays the live JPEG video stream. The server URL is hardcoded in a config file — the app launches straight to the stream view with no server discovery UI. This phase delivers a functional viewer: open the app, see the baby monitor.

## Context for this phase

The baby monitor system streams video from a USB webcam through a Python/aiohttp server as binary JPEG frames over WebSocket at `/stream`. The existing React web client connects, receives `ArrayBuffer` frames, wraps them as JPEG blobs, and displays them in an `<img>` tag.

This phase builds the iOS equivalent: a `URLSessionWebSocketTask` receives the same binary frames, decodes each as a `UIImage`, and displays it in a SwiftUI `Image` view. The server URL is hardcoded to `wss://subglobous-pawky-mark.ngrok-free.dev/stream`.

The server's WebSocket protocol is already defined and working:
- Endpoint: `ws(s)://<host>/stream` (WebSocket upgrade on GET)
- Each message: binary, one complete JPEG image
- No application-level handshake or framing beyond WebSocket

## Technical implementation detail

### 1. Layout

```
ios/
  project.yml                                    (XcodeGen spec)
  BabyMonitor/
    BabyMonitorApp.swift                         (app entry point)
    Config.swift                                 (hardcoded server URL)
    Services/
      WebSocketManager.swift                     (WebSocket + frame decoding)
    Views/
      ContentView.swift                          (root view → StreamView)
      StreamView.swift                           (video display)
    Assets.xcassets/
      Contents.json                              (catalog root)
      AppIcon.appiconset/
        Contents.json                            (icon placeholder)
```

### 2. Data and APIs

#### Config constants

```swift
enum Config {
    static let serverName = "Baby Monitor"
    static let streamURL = URL(string: "wss://subglobous-pawky-mark.ngrok-free.dev/stream")!
    static let healthURL = URL(string: "https://subglobous-pawky-mark.ngrok-free.dev/health")!
}
```

To change the server, edit these constants and rebuild. No runtime configuration needed.

#### Server APIs consumed

**WebSocket stream** (existing):
- URL: `wss://subglobous-pawky-mark.ngrok-free.dev/stream`
- Messages: binary, each is a complete JPEG image
- The app opens the WebSocket, enters a receive loop, and decodes each message as `UIImage(data:)`

**Health check** (from Phase 1, optional):
- `GET https://subglobous-pawky-mark.ngrok-free.dev/health`
- Called on app launch to verify the server is reachable before opening WebSocket
- If the endpoint doesn't exist (Phase 1 not yet done), the app skips validation and connects directly

### 3. Data flow

#### Connect and stream flow

1. App launches → ContentView presents StreamView immediately
2. StreamView creates WebSocketManager with `Config.streamURL`
3. WebSocketManager sets `state = .connecting`
4. WebSocketManager creates `URLSessionWebSocketTask` with the WebSocket URL
5. Task calls `.resume()` → WebSocket handshake
6. On successful connection: `state = .live`
7. Enter receive loop: `task.receive { result in ... }`
   - `.success(.data(let data))` → `UIImage(data: data)` → set `currentFrame` (published property)
   - `.success(.string(_))` → ignore (server only sends binary)
   - `.failure(let error)` → `state = .disconnected`, log error
8. SwiftUI StreamView observes `currentFrame` → displays as `Image(uiImage:)`

#### Optional health check on launch

Before connecting the WebSocket, StreamView can do a quick health check:
```swift
func checkHealth() async -> Bool {
    do {
        let (data, response) = try await URLSession.shared.data(from: Config.healthURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return true
    } catch {
        return false
    }
}
```

If the health check fails, show "Server unreachable" with a retry button. If it succeeds (or is skipped), proceed to WebSocket connection.

### 4. Integrations

**URLSession (WebSocket):** `URLSessionWebSocketTask` is Apple's native WebSocket client. Created via `URLSession.shared.webSocketTask(with: url)`. Receives messages via `task.receive(completionHandler:)` in a loop. Automatically handles ping/pong (responds to server pings). Supports both `ws://` and `wss://` schemes.

### 5. XcodeGen project spec

The `project.yml` defines the Xcode project without requiring a hand-written `.xcodeproj`:

```yaml
name: BabyMonitor
options:
  bundleIdPrefix: com.babymonitor
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "15.0"
targets:
  BabyMonitor:
    type: application
    platform: iOS
    sources:
      - path: BabyMonitor
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.babymonitor.viewer
        SWIFT_VERSION: "5.9"
        TARGETED_DEVICE_FAMILY: "1"
        SUPPORTS_XR_DESIGNED_FOR: false
```

Generate the Xcode project: `cd ios && xcodegen generate`. Open `BabyMonitor.xcodeproj` in Xcode.

### 6. Key implementation details

#### WebSocketManager

```swift
@Observable
final class WebSocketManager {
    enum ConnectionState { case disconnected, connecting, live }

    var state: ConnectionState = .disconnected
    var currentFrame: UIImage?

    private var task: URLSessionWebSocketTask?
    private let url: URL

    init(url: URL) { self.url = url }

    func connect() {
        state = .connecting
        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        state = .live
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        state = .disconnected
        currentFrame = nil
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.data(let data)):
                let image = UIImage(data: data)
                Task { @MainActor in self.currentFrame = image }
                self.receiveLoop()
            case .success(.string):
                self.receiveLoop()
            case .failure:
                Task { @MainActor in self.state = .disconnected }
            @unknown default:
                break
            }
        }
    }
}
```

The `@Observable` macro (iOS 17+) replaces `ObservableObject` + `@Published`. SwiftUI views automatically track property access and re-render when `currentFrame` or `state` changes.

#### StreamView rendering

```swift
struct StreamView: View {
    @State private var manager = WebSocketManager(url: Config.streamURL)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let frame = manager.currentFrame {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }

            if manager.state != .live {
                VStack {
                    ProgressView()
                        .tint(.white)
                    Text(manager.state == .connecting ? "Connecting..." : "Disconnected")
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                }
            }
        }
        .onAppear { manager.connect() }
        .onDisappear { manager.disconnect() }
    }
}
```

#### ContentView

```swift
struct ContentView: View {
    var body: some View {
        StreamView()
    }
}
```

Minimal — just presents StreamView. Phase 3 adds night mode state here. Phase 4 adds scenePhase handling in BabyMonitorApp.

## Deliverables Manifest

1. NEW  `ios/project.yml` — XcodeGen project spec: iOS 17+ deployment target, SwiftUI lifecycle, bundle ID `com.babymonitor.viewer`, device family iPhone only
2. NEW  `ios/BabyMonitor/BabyMonitorApp.swift` — `@main` app entry with `WindowGroup { ContentView() }`
3. NEW  `ios/BabyMonitor/Config.swift` — Enum with static constants: `serverName` ("Baby Monitor"), `streamURL` (`wss://subglobous-pawky-mark.ngrok-free.dev/stream`), `healthURL` (`https://subglobous-pawky-mark.ngrok-free.dev/health`)
4. NEW  `ios/BabyMonitor/Services/WebSocketManager.swift` — `@Observable` class: `URLSessionWebSocketTask` lifecycle, binary frame receive loop, JPEG → `UIImage` decoding, `ConnectionState` enum (disconnected/connecting/live), `currentFrame: UIImage?` property, `connect()` and `disconnect()` methods
5. NEW  `ios/BabyMonitor/Views/ContentView.swift` — Root view that directly presents `StreamView`
6. NEW  `ios/BabyMonitor/Views/StreamView.swift` — Black background, `Image(uiImage:)` from `WebSocketManager.currentFrame` with `.aspectRatio(.fit)`, connection status overlay with `ProgressView` when connecting and text when disconnected, `onAppear`/`onDisappear` connect/disconnect lifecycle
7. NEW  `ios/BabyMonitor/Assets.xcassets/Contents.json` — `{"info": {"version": 1, "author": "xcode"}}`
8. NEW  `ios/BabyMonitor/Assets.xcassets/AppIcon.appiconset/Contents.json` — Empty app icon configuration (no images, placeholder for future icon)

**Implementation protocol:** The implementing agent must follow the `plan-implementation` cursor rule when executing this phase.

## Acceptance criteria

- [ ] `xcodegen generate` in `ios/` produces a valid `BabyMonitor.xcodeproj`
- [ ] Project builds without errors in Xcode 15+ targeting iOS 17+
- [ ] App launches directly to the stream view (no server list, no setup screens)
- [ ] App connects to `wss://subglobous-pawky-mark.ngrok-free.dev/stream` and displays the live JPEG stream
- [ ] Connection status shows "Connecting..." then disappears when live
- [ ] If the server is unreachable, the app shows "Disconnected"
- [ ] Backgrounding and foregrounding the app doesn't crash (basic lifecycle)

## Test plan

1. **Project generation:**
   - Install xcodegen: `brew install xcodegen`
   - `cd ios && xcodegen generate`
   - Open `BabyMonitor.xcodeproj` in Xcode — verify no build errors

2. **Stream via ngrok (device or simulator):**
   - Start the baby monitor server with ngrok configured: `cd server && python main.py`
   - Run the iOS app on a device or simulator
   - Verify the video stream appears automatically on launch

3. **Stream locally (simulator only):**
   - Start the server without ngrok: `cd server && python main.py`
   - Temporarily change `Config.streamURL` to `ws://localhost:8765/stream` for testing
   - Run in Simulator → verify stream displays

4. **Disconnect handling:**
   - See the stream, then stop the Python server
   - Verify StreamView shows "Disconnected"

5. **App lifecycle:**
   - While streaming, press home button → reopen app
   - Verify no crash (stream may need to reconnect — Phase 3 handles auto-reconnect)

## Interface contract (for subsequent phases)

- **WebSocketManager API:** `@Observable` class with `state: ConnectionState` (.disconnected/.connecting/.live), `currentFrame: UIImage?`, `connect()`, `disconnect()`. Located at `ios/BabyMonitor/Services/WebSocketManager.swift`.
- **Config:** `Config.streamURL`, `Config.healthURL`, `Config.serverName` at `ios/BabyMonitor/Config.swift`. Phase 4 reads `healthURL` and `serverName` for background checks and notifications.
- **ContentView:** Located at `ios/BabyMonitor/Views/ContentView.swift`. Currently just wraps StreamView. Phase 3 adds night mode state here.
- **StreamView:** Located at `ios/BabyMonitor/Views/StreamView.swift`. Owns its `WebSocketManager` instance as `@State`. Phase 3 adds fullscreen/night mode to this view.

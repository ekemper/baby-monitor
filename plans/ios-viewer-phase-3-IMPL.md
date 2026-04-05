# iOS Viewer App — Phase 3: Enhanced UX

**Master plan:** [ios-viewer-PLAN.md](ios-viewer-PLAN.md)
**Phase:** 3 of 4
**Prerequisites:** Phase 2 must be complete (the iOS app with `WebSocketManager`, `StreamView`, `ContentView`, and `Config` must exist at the paths listed below)
**Parallel tracks:** No — sequential
**Estimated scope:** medium

## Summary

Polish the iOS viewer app for comfortable daily use as a baby monitor. Add fullscreen mode (tap to toggle chrome), landscape support with adaptive layout, automatic reconnection with exponential backoff, and a night mode overlay that dims the screen with a warm amber tint for nighttime monitoring.

## Context for this phase

The baby monitor iOS app (Phase 2) connects to a hardcoded server URL and displays the JPEG video stream. But it lacks the fit-and-finish needed for a baby monitor you leave running on a nightstand:

- No fullscreen — status bar and home indicator waste screen space
- No auto-reconnect — if WiFi blips, the user must manually restart the app
- No night mode — a bright screen is disruptive in a dark nursery

This phase addresses all of these. The files modified were created in Phase 2:

- `ios/BabyMonitor/Views/StreamView.swift` — video display view
- `ios/BabyMonitor/Services/WebSocketManager.swift` — WebSocket connection manager
- `ios/BabyMonitor/Views/ContentView.swift` — root view

## Technical implementation detail

### 1. Layout

```
ios/BabyMonitor/
  Views/
    StreamView.swift           (MOD — fullscreen, landscape, night mode toggle)
    ContentView.swift          (MOD — night mode state)
    NightModeOverlay.swift     (NEW — amber overlay)
  Services/
    WebSocketManager.swift     (MOD — auto-reconnect)
  Storage/
    PreferencesStorage.swift   (NEW — night mode preference)
```

### 2. Fullscreen mode

StreamView adds a `@State private var isFullscreen: Bool = false` toggle. Behavior:

- **Tap anywhere on the video** to toggle fullscreen
- **Fullscreen on:** hide status bar (`.statusBarHidden(true)`), hide home indicator (`.persistentSystemOverlays(.hidden)`)
- **Fullscreen off:** restore all chrome
- **Auto-enter fullscreen** after 5 seconds of streaming (use `.task` with `try await Task.sleep`)
- Fullscreen state does not persist — always starts non-fullscreen on launch

### 3. Landscape support

StreamView uses `.aspectRatio(contentMode: .fit)` which naturally adapts to both orientations:

- **Portrait:** video fills width, maintains 4:3 aspect ratio
- **Landscape:** video fills the entire screen with correct aspect ratio
- Support all orientations in the Xcode project settings (already default for SwiftUI apps)
- The connection status overlay uses a centered `VStack` that works in both orientations

No special layout code is needed beyond what SwiftUI provides — `.aspectRatio(.fit)` with a black background naturally adapts. The key is ensuring the status overlay and night mode toggle don't break in landscape.

### 4. Auto-reconnect with exponential backoff

WebSocketManager gains a reconnection system:

```swift
// New properties
var reconnectAttempt: Int = 0
private var reconnectTask: Task<Void, Never>?
private static let backoffIntervals: [TimeInterval] = [1, 2, 4, 8, 16, 30]

func scheduleReconnect() {
    guard state == .disconnected else { return }
    let delay = Self.backoffIntervals[min(reconnectAttempt, Self.backoffIntervals.count - 1)]
    reconnectAttempt += 1
    state = .reconnecting
    reconnectTask = Task {
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled else { return }
        connect()
    }
}
```

Changes to `ConnectionState` enum:
- Add `.reconnecting` case
- The UI shows "Reconnecting (attempt N)..." with the attempt count

Reconnect behavior:
- On disconnect (receive loop failure), call `scheduleReconnect()` automatically
- On successful connection, reset `reconnectAttempt = 0`
- On manual `disconnect()` (user backgrounds app or app is being torn down), cancel `reconnectTask` — do not auto-reconnect
- Cap at 30s between attempts (last element in backoff array repeats)

Add a `var shouldAutoReconnect: Bool = true` property. Set to `false` when the user explicitly disconnects. Set to `true` when connecting.

### 5. Night mode

Night mode reduces screen brightness and applies a warm amber overlay — ideal for a dark nursery where you glance at the monitor occasionally.

**NightModeOverlay.swift:**
```swift
struct NightModeOverlay: View {
    var body: some View {
        Color.orange
            .opacity(0.3)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
```

**State management:**
- `ContentView` holds `@State private var isNightMode: Bool` initialized from `PreferencesStorage.loadNightMode()`
- Passed to StreamView via init parameter or `.environment()`
- StreamView toolbar has a moon icon button to toggle night mode
- When toggled on: overlay NightModeOverlay on top of everything, reduce `UIScreen.main.brightness` by 50% (save original value, restore on toggle off)
- Persist preference via `PreferencesStorage.saveNightMode(_:)`

**Brightness management:**
- Store the original brightness in a `@State` var before reducing
- Restore it in `.onDisappear` and when night mode is toggled off
- Use `UIScreen.main.brightness` (UIKit interop, fully supported in SwiftUI)

### 6. PreferencesStorage

```swift
enum PreferencesStorage {
    private static let nightModeKey = "night_mode_enabled"

    static func loadNightMode() -> Bool {
        UserDefaults.standard.bool(forKey: nightModeKey)
    }

    static func saveNightMode(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: nightModeKey)
    }
}
```

## Deliverables Manifest

1. MOD  `ios/BabyMonitor/Views/StreamView.swift` — Add `isFullscreen` state with tap-to-toggle gesture on the video area; hide status bar and home indicator when fullscreen; auto-enter fullscreen after 5s of live streaming; landscape-adaptive layout (verify `.aspectRatio(.fit)` works in both orientations); add night mode toggle button (moon icon) as an overlay button
2. MOD  `ios/BabyMonitor/Services/WebSocketManager.swift` — Add `.reconnecting` to `ConnectionState` enum; add `reconnectAttempt` counter and `shouldAutoReconnect` flag; add `scheduleReconnect()` with exponential backoff (1s→2s→4s→8s→16s→30s cap); call `scheduleReconnect()` on receive loop failure when `shouldAutoReconnect` is true; reset attempt counter on successful connection; cancel reconnect task on explicit `disconnect()`
3. NEW  `ios/BabyMonitor/Views/NightModeOverlay.swift` — Semi-transparent amber `Color.orange.opacity(0.3)` overlay, ignores safe area, passes through touches (`allowsHitTesting(false)`)
4. MOD  `ios/BabyMonitor/Views/ContentView.swift` — Add `@State isNightMode` initialized from `PreferencesStorage.loadNightMode()`; pass to StreamView; conditionally overlay `NightModeOverlay` when enabled; manage `UIScreen.main.brightness` reduction (save original, restore on toggle off and onDisappear)
5. NEW  `ios/BabyMonitor/Storage/PreferencesStorage.swift` — Enum with static methods: `loadNightMode() -> Bool` and `saveNightMode(_ enabled: Bool)` using UserDefaults key `"night_mode_enabled"`

**Implementation protocol:** The implementing agent must follow the `plan-implementation` cursor rule when executing this phase.

## Acceptance criteria

- [ ] Tapping the video in StreamView toggles fullscreen (hides status bar and home indicator)
- [ ] Tapping again exits fullscreen and restores chrome
- [ ] StreamView auto-enters fullscreen after 5 seconds of live streaming
- [ ] Rotating to landscape shows the video filling the screen with correct aspect ratio (no stretching)
- [ ] When the server stops, the app shows "Reconnecting (attempt 1)..." and retries
- [ ] Reconnect attempts follow exponential backoff (1s, 2s, 4s, 8s, 16s, 30s, 30s, ...)
- [ ] When the server comes back, the stream resumes and the attempt counter resets
- [ ] Tapping the moon icon enables night mode: amber overlay appears, screen dims
- [ ] Tapping the moon icon again disables night mode: overlay gone, brightness restored
- [ ] Night mode preference persists across app launches

## Test plan

1. **Fullscreen:**
   - Launch app, connect to server → wait 5s → verify fullscreen auto-activates
   - Tap screen → verify status bar reappears
   - Tap again → verify fullscreen returns

2. **Landscape:**
   - Connect to server in portrait → rotate device to landscape
   - Verify video fills width, aspect ratio preserved, no stretching
   - Rotate back → verify portrait layout

3. **Auto-reconnect:**
   - Connect to server → stop the Python server
   - Verify "Reconnecting (attempt 1)..." appears after ~1s
   - Wait and verify attempt count increases: 2, 3, 4...
   - Restart the Python server → verify stream resumes, status returns to live

4. **Night mode:**
   - Tap moon icon while streaming
   - Verify amber overlay appears and screen brightness decreases
   - Tap moon icon again → verify overlay gone, brightness restored
   - Enable night mode → kill app → reopen → verify night mode is still on

## Interface contract (for subsequent phases)

- **WebSocketManager.state** now includes `.reconnecting` in addition to `.disconnected`, `.connecting`, `.live`. Phase 4 checks state to determine if the app should fire a disconnect notification.
- **WebSocketManager.shouldAutoReconnect** — boolean flag. Phase 4 sets this to `true` when backgrounding to ensure reconnect attempts continue.
- **Night mode** — managed in ContentView. Phase 4 doesn't need to modify it.
- **PreferencesStorage** — night mode only. Phase 4 doesn't add to it.

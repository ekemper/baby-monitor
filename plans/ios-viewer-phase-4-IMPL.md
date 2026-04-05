# iOS Viewer App — Phase 4: Background & Notifications

**Master plan:** [ios-viewer-PLAN.md](ios-viewer-PLAN.md)
**Phase:** 4 of 4
**Prerequisites:** Phase 2 must be complete (`WebSocketManager` at `ios/BabyMonitor/Services/WebSocketManager.swift` with `state`, `connect()`, `disconnect()`, and `Config` at `ios/BabyMonitor/Config.swift` must exist). Phase 3 should be complete (`shouldAutoReconnect` flag and `.reconnecting` state in WebSocketManager).
**Parallel tracks:** No — sequential
**Estimated scope:** medium

## Summary

Add background connection monitoring and local disconnect notifications so the baby monitor app alerts the parent if the server goes offline while the app is backgrounded (phone locked or switched to another app). Uses `BGTaskScheduler` for periodic health checks and `UNUserNotificationCenter` for local alerts. This is the final phase — after this, the app is a reliable daily-use baby monitor viewer.

## Context for this phase

The baby monitor iOS app (Phases 2-3) displays a live video stream with auto-reconnect, fullscreen, and night mode. The server URL is hardcoded in `Config.swift`. But when the user backgrounds the app, the WebSocket connection eventually dies and the user has no way to know the monitor went offline.

This phase adds:
1. **Background health checks** — when the app enters background, schedule a `BGAppRefreshTask` that periodically pings `Config.healthURL`
2. **Local disconnect notification** — if the health check fails, fire a local notification: "Baby Monitor Disconnected"
3. **Foreground/background transitions** — gracefully handle the WebSocket lifecycle across scene phase changes

Key files from prior phases:
- `ios/BabyMonitor/Services/WebSocketManager.swift` — connection manager with `state`, `shouldAutoReconnect`, `connect()`, `disconnect()`
- `ios/BabyMonitor/Config.swift` — hardcoded `healthURL` and `serverName`
- `ios/BabyMonitor/BabyMonitorApp.swift` — app entry point

### iOS background execution constraints

`BGAppRefreshTask` is the appropriate API for this use case. Key constraints the implementation must account for:

- **Not real-time.** iOS decides when to run the task based on usage patterns, battery, network. The task may run within minutes or hours of being scheduled. This is acceptable — the notification is best-effort.
- **~30 seconds of execution time.** Enough for an HTTP health check, but not for maintaining a WebSocket connection.
- **Must be re-scheduled after each execution.** The task handler must schedule the next check before completing.
- **Task identifier must be registered in Info.plist** via `BGTaskSchedulerPermittedIdentifiers`.

The implementation does NOT try to keep a WebSocket alive in the background — that's unreliable and battery-draining. Instead, it does a lightweight HTTP health check.

## Technical implementation detail

### 1. Layout

```
ios/BabyMonitor/
  BabyMonitorApp.swift               (MOD — register task, handle scenePhase)
  Services/
    WebSocketManager.swift           (MOD — background state hooks)
    BackgroundMonitor.swift          (NEW — BGTaskScheduler wrapper)
    NotificationManager.swift        (NEW — local notification wrapper)
ios/project.yml                      (MOD — Info.plist additions)
```

### 2. Data and APIs

#### BGTaskScheduler

- **Task identifier:** `com.babymonitor.connectionCheck`
- **Registered in:** `BabyMonitorApp.init()` via `BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)`
- **Scheduled:** when app enters `.background` scene phase
- **Handler:** performs `GET /health` on `Config.healthURL`, fires notification on failure, re-schedules the next check

#### UNUserNotificationCenter

- **Permission request:** on first app launch (in `BabyMonitorApp.onAppear`)
- **Notification content:**
  - Title: "Baby Monitor Disconnected"
  - Body: "\(Config.serverName) is no longer reachable"
  - Sound: `.default`

#### Health check API (from Phase 1)

- `GET https://subglobous-pawky-mark.ngrok-free.dev/health` → 200 with JSON
- If this returns non-200 or times out (5s), the server is considered unreachable

### 3. Data flow

#### App enters background

1. `BabyMonitorApp` detects `.background` via `@Environment(\.scenePhase)`
2. Calls `BackgroundMonitor.scheduleHealthCheck()`
3. WebSocketManager continues running (iOS may keep it alive briefly), with `shouldAutoReconnect = true`
4. Eventually iOS suspends the app — WebSocket dies

#### Background task fires

1. iOS launches the app in background and calls the registered task handler
2. `BackgroundMonitor.handleHealthCheck(task:)`:
   a. Perform `GET /health` on `Config.healthURL` with a 5-second timeout
   b. **Success (200):** server is alive → re-schedule next check in ~15 minutes → `task.setTaskCompleted(success: true)`
   c. **Failure (timeout, non-200, network error):** server unreachable → call `NotificationManager.postDisconnectNotification()` → re-schedule → `task.setTaskCompleted(success: true)`
3. `task.expirationHandler` — if iOS kills the task before completion, re-schedule

#### App returns to foreground

1. `BabyMonitorApp` detects `.active` via `scenePhase`
2. If WebSocketManager is in `.disconnected` or `.reconnecting` state, trigger `connect()`
3. Cancel any pending background tasks (they'll be re-scheduled on next background entry)

### 4. Integrations

**BGTaskScheduler** (BackgroundTasks framework):
```swift
import BackgroundTasks

// Registration (in BabyMonitorApp.init)
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.babymonitor.connectionCheck",
    using: nil
) { task in
    BackgroundMonitor.handleHealthCheck(task: task as! BGAppRefreshTask)
}

// Scheduling
let request = BGAppRefreshTaskRequest(identifier: "com.babymonitor.connectionCheck")
request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
try BGTaskScheduler.shared.submit(request)
```

**UNUserNotificationCenter** (UserNotifications framework):
```swift
import UserNotifications

// Permission
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in }

// Post notification
let content = UNMutableNotificationContent()
content.title = "Baby Monitor Disconnected"
content.body = "\(Config.serverName) is no longer reachable"
content.sound = .default
let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
UNUserNotificationCenter.current().add(request)
```

### 5. Key implementation details

#### BackgroundMonitor.swift

```swift
import BackgroundTasks

enum BackgroundMonitor {
    static let taskIdentifier = "com.babymonitor.connectionCheck"

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            handleHealthCheck(task: task as! BGAppRefreshTask)
        }
    }

    static func scheduleHealthCheck() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancelPendingChecks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    static func handleHealthCheck(task: BGAppRefreshTask) {
        scheduleHealthCheck()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            let reachable = await performHealthCheck()
            if !reachable {
                NotificationManager.postDisconnectNotification()
            }
            task.setTaskCompleted(success: true)
        }
    }

    private static func performHealthCheck() async -> Bool {
        var request = URLRequest(url: Config.healthURL)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
```

#### NotificationManager.swift

```swift
import UserNotifications

enum NotificationManager {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    static func postDisconnectNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Baby Monitor Disconnected"
        content.body = "\(Config.serverName) is no longer reachable"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "disconnect-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

#### BabyMonitorApp.swift changes

```swift
@main
struct BabyMonitorApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundMonitor.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NotificationManager.requestPermission()
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                BackgroundMonitor.scheduleHealthCheck()
            case .active:
                BackgroundMonitor.cancelPendingChecks()
            default:
                break
            }
        }
    }
}
```

#### WebSocketManager changes

Add an `isAppBackgrounded` property. When the receive loop fails and `isAppBackgrounded` is true, call `NotificationManager.postDisconnectNotification()` directly (in addition to the BGTask-based check, which handles the case where the WebSocket was already dead when the app backgrounded).

```swift
// In the receive loop failure case:
case .failure:
    Task { @MainActor in
        self.state = .disconnected
        if self.isAppBackgrounded {
            NotificationManager.postDisconnectNotification()
        }
        if self.shouldAutoReconnect {
            self.scheduleReconnect()
        }
    }
```

### 6. project.yml changes

Add the BGTaskScheduler permitted identifiers to Info.plist settings:

```yaml
targets:
  BabyMonitor:
    info:
      properties:
        BGTaskSchedulerPermittedIdentifiers:
          - com.babymonitor.connectionCheck
```

Use whichever format xcodegen supports for array plist values — check xcodegen docs during implementation.

## Deliverables Manifest

1. MOD  `ios/BabyMonitor/BabyMonitorApp.swift` — Call `BackgroundMonitor.register()` in `init()`; add `@Environment(\.scenePhase)` observer; on `.background` schedule health check; on `.active` cancel pending checks; call `NotificationManager.requestPermission()` in `.onAppear`
2. NEW  `ios/BabyMonitor/Services/BackgroundMonitor.swift` — Enum with static methods: `register()` (registers BGTask handler), `scheduleHealthCheck()` (submits BGAppRefreshTaskRequest with 15-min earliest begin date using `Config.healthURL`), `cancelPendingChecks()`, `handleHealthCheck(task:)` (performs GET /health with 5s timeout, fires notification on failure via `NotificationManager`, re-schedules next check)
3. NEW  `ios/BabyMonitor/Services/NotificationManager.swift` — Enum with static methods: `requestPermission()` (requests .alert, .sound, .badge authorization), `postDisconnectNotification()` (posts local notification with title "Baby Monitor Disconnected" and `Config.serverName` in body)
4. MOD  `ios/BabyMonitor/Services/WebSocketManager.swift` — Add `isAppBackgrounded: Bool` property; on receive loop failure when backgrounded, call `NotificationManager.postDisconnectNotification()`; ensure `shouldAutoReconnect` continues working when backgrounded
5. MOD  `ios/project.yml` — Add `BGTaskSchedulerPermittedIdentifiers` array with `com.babymonitor.connectionCheck` to Info.plist properties

**Implementation protocol:** The implementing agent must follow the `plan-implementation` cursor rule when executing this phase.

## Acceptance criteria

- [ ] App requests notification permission on first launch
- [ ] When app is backgrounded while connected, a BGAppRefreshTask is scheduled
- [ ] When the background task fires and the server is unreachable, a local notification appears: "Baby Monitor Disconnected"
- [ ] When the background task fires and the server IS reachable, no notification fires and the next check is scheduled
- [ ] When app returns to foreground, pending background tasks are cancelled
- [ ] If the WebSocket disconnects while the app is in background (brief iOS grace period), a notification fires immediately
- [ ] The app does not crash or misbehave during background/foreground transitions
- [ ] `BGTaskSchedulerPermittedIdentifiers` is correctly set in the generated Info.plist (verify via `xcodegen generate` and inspecting the project)

## Test plan

1. **Notification permission:**
   - Fresh install → launch app → verify permission dialog appears
   - Grant permission → verify no repeated prompts

2. **Background health check (simulated):**
   - Connect to the server, background the app
   - In Xcode debugger, simulate the background task:
     ```
     e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.babymonitor.connectionCheck"]
     ```
   - With server running → verify no notification
   - Stop the server → simulate task again → verify notification appears

3. **Foreground resume:**
   - Connect to server → background app → wait a moment → foreground
   - If server is still running → verify stream resumes
   - If server was stopped → verify app shows reconnecting state

4. **Immediate disconnect notification:**
   - Connect to server → background app → immediately stop the server
   - Verify notification appears within a few seconds (iOS grace period)

5. **Project configuration:**
   - Run `cd ios && xcodegen generate`
   - Open project in Xcode → Build Settings → verify `BGTaskSchedulerPermittedIdentifiers` contains `com.babymonitor.connectionCheck`

## Interface contract (for subsequent phases)

N/A — this is the final phase.

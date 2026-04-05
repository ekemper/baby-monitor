# iOS Viewer App — Questions

All clarifying questions were resolved during the collaborative design session. See the plan for decisions made:

- **Framework:** SwiftUI (native, iOS 17+, @Observable macro)
- **WebSocket client:** URLSessionWebSocketTask (Apple-native, no third-party deps)
- **Multi-viewer:** Yes — server modified to support concurrent clients
- **Server discovery:** Both QR code scanning and manual URL entry
- **Feature scope:** Full — fullscreen, landscape, reconnect, saved servers, night mode, background monitoring, disconnect notifications
- **Notifications:** Local only (UNUserNotificationCenter, no APNs server)
- **ngrok:** Integrated via pyngrok with reserved domain (NGROK_DOMAIN env var)
- **Server changes:** In scope alongside the iOS app
- **Persistence:** UserDefaults (simple, sufficient for server list + preferences)
- **Project generation:** xcodegen from project.yml

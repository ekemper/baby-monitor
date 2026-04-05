import SwiftUI

struct StreamView: View {
    @Binding var isNightMode: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var manager = WebSocketManager(url: Config.streamURL)
    @State private var isFullscreen = false

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
                    statusText
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                }
            }

            // Night mode toggle button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isNightMode.toggle()
                    } label: {
                        Image(systemName: isNightMode ? "moon.fill" : "moon")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(12)
                    }
                }
                Spacer()
            }
            .opacity(isFullscreen ? 0 : 1)
            .allowsHitTesting(!isFullscreen)
        }
        .onTapGesture {
            isFullscreen.toggle()
        }
        .statusBarHidden(isFullscreen)
        .persistentSystemOverlays(isFullscreen ? .hidden : .automatic)
        .onAppear { manager.connect() }
        .onDisappear { manager.disconnect() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                manager.isAppBackgrounded = true
            case .active:
                manager.isAppBackgrounded = false
                if manager.state == .disconnected || manager.state == .reconnecting {
                    manager.connect()
                }
            default:
                break
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(5))
            if manager.state == .live {
                isFullscreen = true
            }
        }
    }

    private var statusText: Text {
        switch manager.state {
        case .connecting:
            Text("Connecting...")
        case .reconnecting:
            Text("Reconnecting (attempt \(manager.reconnectAttempt))...")
        case .disconnected:
            Text("Disconnected")
        case .live:
            Text("")
        }
    }
}

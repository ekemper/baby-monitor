import SwiftUI

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
        .onChange(of: scenePhase) { _, newPhase in
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

import SwiftUI

struct ContentView: View {
    @State private var isNightMode = PreferencesStorage.loadNightMode()
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness

    var body: some View {
        ZStack {
            StreamView(isNightMode: $isNightMode)

            if isNightMode {
                NightModeOverlay()
            }
        }
        .onChange(of: isNightMode) { _, newValue in
            PreferencesStorage.saveNightMode(newValue)
            if newValue {
                originalBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = originalBrightness * 0.5
            } else {
                UIScreen.main.brightness = originalBrightness
            }
        }
        .onDisappear {
            if isNightMode {
                UIScreen.main.brightness = originalBrightness
            }
        }
    }
}

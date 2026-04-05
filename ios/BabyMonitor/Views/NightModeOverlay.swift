import SwiftUI

struct NightModeOverlay: View {
    var body: some View {
        Color.orange
            .opacity(0.3)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

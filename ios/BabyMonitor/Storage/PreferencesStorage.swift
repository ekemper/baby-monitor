import Foundation

enum PreferencesStorage {
    private static let nightModeKey = "night_mode_enabled"

    static func loadNightMode() -> Bool {
        UserDefaults.standard.bool(forKey: nightModeKey)
    }

    static func saveNightMode(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: nightModeKey)
    }
}

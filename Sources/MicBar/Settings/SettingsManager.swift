import Foundation

final class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let displayStyle = "displayStyle"
        static let launchAtLogin = "launchAtLogin"
    }

    var displayStyle: DisplayStyle {
        get {
            let raw = defaults.integer(forKey: Keys.displayStyle)
            return DisplayStyle(rawValue: raw) ?? .textOnly
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.displayStyle)
        }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    private init() {}
}

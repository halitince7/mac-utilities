import Foundation
import Combine

/// Persisted feature toggles, shared across the engine and the UI.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let store = UserDefaults.standard

    @Published var desktopSwitcher: Bool { didSet { store.set(desktopSwitcher, forKey: "desktopSwitcher") } }
    @Published var scrollFix: Bool { didSet { store.set(scrollFix, forKey: "scrollFix") } }

    private init() {
        store.register(defaults: ["desktopSwitcher": true, "scrollFix": true])
        desktopSwitcher = store.bool(forKey: "desktopSwitcher")
        scrollFix = store.bool(forKey: "scrollFix")
    }
}

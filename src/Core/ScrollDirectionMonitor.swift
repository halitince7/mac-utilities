import Foundation

/// Tracks the global macOS "Natural Scrolling" setting so ScrollFix works the
/// same regardless of how the user has it configured. macOS applies ONE global
/// direction to both mouse and trackpad; we read it and invert the right device
/// to always land on: mouse = traditional, trackpad = natural.
final class ScrollDirectionMonitor {
    static let shared = ScrollDirectionMonitor()
    private(set) var naturalScrollingOn = true
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        var exists: DarwinBoolean = false
        let value = CFPreferencesGetAppBooleanValue(
            "com.apple.swipescrolldirection" as CFString,
            kCFPreferencesAnyApplication, &exists)
        // macOS default (when unset) is natural scrolling ON.
        naturalScrollingOn = exists.boolValue ? value : true
    }
}

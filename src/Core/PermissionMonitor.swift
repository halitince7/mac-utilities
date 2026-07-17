import Cocoa
import Combine

/// Polls the Accessibility trust state and publishes it to the UI banner.
final class PermissionMonitor: ObservableObject {
    static let shared = PermissionMonitor()
    @Published var trusted: Bool = AXIsProcessTrusted()
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            let now = AXIsProcessTrusted()
            if now != self?.trusted { self?.trusted = now }
        }
    }
}

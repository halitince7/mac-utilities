import Foundation

enum Const {
    static let bundleID = "com.mathatinlabs.macutilities"
    static let showUINotification = Notification.Name("com.mathatinlabs.macutilities.showUI")

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

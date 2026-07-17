import Cocoa

// Entry point. Top-level executable statements are only allowed in main.swift.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Menu bar app: no Dock icon
app.run()

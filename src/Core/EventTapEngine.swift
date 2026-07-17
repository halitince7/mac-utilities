import Cocoa

/// Core engine: a single CGEvent tap that dispatches scroll/flag events to the
/// enabled features. One process, one permission (Accessibility).
final class FeatureEngine: NSObject {
    private var ctrlPressed = false
    private var lastScrollTime: TimeInterval = 0
    private let scrollCooldown: TimeInterval = 0.2

    private var eventTap: CFMachPort?
    private var retryTimer: Timer?

    private let settings = AppSettings.shared
    private let scrollDir = ScrollDirectionMonitor.shared

    func start() {
        // Ask for the permission once (passes immediately if already granted).
        // Do NOT terminate when it is missing — this avoids the old
        // "terminate + KeepAlive" infinite permission-prompt loop.
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        setupTapIfPossible()

        // If permission is not granted yet: retry periodically WITHOUT re-prompting.
        if eventTap == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                guard AXIsProcessTrusted() else { return }   // wait silently
                self.setupTapIfPossible()
                if self.eventTap != nil {
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                }
            }
        }
    }

    private func setupTapIfPossible() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }

        let eventMask = (1 << CGEventType.scrollWheel.rawValue)
                      | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let mySelf = Unmanaged<FeatureEngine>.fromOpaque(refcon).takeUnretainedValue()
                return mySelf.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: Event dispatch
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .flagsChanged:
            ctrlPressed = event.flags.contains(.maskControl)

        case .scrollWheel:
            // Feature 1: Ctrl + scroll switches desktops (consumes the event).
            if ctrlPressed && settings.desktopSwitcher {
                handleDesktopSwitch(event)
                return nil
            }
            // Feature 2: ScrollFix.
            if settings.scrollFix {
                applyScrollFix(event)
            }

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: Feature 1 — Desktop Switcher
    private enum Direction { case left, right }

    private func handleDesktopSwitch(_ event: CGEvent) {
        let scrollDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let now = CACurrentMediaTime()
        guard now - lastScrollTime > scrollCooldown, scrollDelta != 0 else { return }
        switchDesktop(direction: scrollDelta > 0 ? .left : .right)
        lastScrollTime = now
    }

    private func switchDesktop(direction: Direction) {
        let keyCode: CGKeyCode = direction == .left ? 123 : 124 // Left / Right arrow
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            down.flags.formUnion(.maskControl)
            up.flags.formUnion(.maskControl)
            down.post(tap: .cghidEventTap)
            usleep(1000)
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: Feature 2 — ScrollFix
    // Goal (independent of the system Natural Scrolling setting):
    //   mouse  -> traditional   |   trackpad -> natural
    // The device is inferred from the scroll event's "continuous" field
    // (notched mouse wheel = false, trackpad = true), so no Input Monitoring
    // permission is required.
    private func applyScrollFix(_ event: CGEvent) {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let isMouse = !isContinuous
        let naturalOn = scrollDir.naturalScrollingOn

        // Mouse wants traditional; trackpad wants natural.
        let shouldInvert = isMouse ? naturalOn : !naturalOn
        guard shouldInvert else { return }

        let dY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let dX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -dY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -dX)

        // For continuous (trackpad / precision) input, also invert the smooth
        // pixel deltas so scrolling stays fluid.
        if isContinuous {
            let pY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let pX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let fY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let fX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pY)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -pX)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fY)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fX)
        }
    }
}

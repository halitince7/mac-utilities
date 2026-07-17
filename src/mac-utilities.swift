#!/usr/bin/swift

import Cocoa
import Foundation

// MARK: - Unified Mac Utilities daemon
//
// Tek process, tek izin (Accessibility). İçinde birden fazla özellik barındırır:
//   1. Desktop Switcher : Ctrl + scroll -> masaüstü değiştir
//   2. ScrollFix        : fare scroll'unu ters çevir (trackpad doğal kalır)
//
// Yeni özellikler eklemek için aşağıya yeni bir "feature" davranışı eklemen
// yeterli; ayrı bir binary / ayrı bir izin gerekmez.

final class MacUtilities: NSObject {

    // MARK: Desktop switcher durumu
    private var ctrlPressed = false
    private var lastScrollTime: TimeInterval = 0
    private let scrollCooldown: TimeInterval = 0.2

    // MARK: Tap
    private var eventTap: CFMachPort?
    private var retryTimer: Timer?

    // MARK: - Başlangıç
    func start() {
        // İzni bir kez iste (varsa hemen geçer). Eksikse KENDİNİ KAPATMA —
        // bu, eski "terminate + KeepAlive" sonsuz izin döngüsünü önler.
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        setupTapIfPossible()

        // İzin henüz yoksa: yeniden SORMADAN periyodik olarak dene.
        if eventTap == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                guard AXIsProcessTrusted() else { return }   // sessizce bekle
                self.setupTapIfPossible()
                if self.eventTap != nil {
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                    fputs("Accessibility granted — utilities active.\n", stderr)
                }
            }
        }

        setupSignalHandler()
    }

    // MARK: - Event tap kurulumu
    private func setupTapIfPossible() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else { return }

        let eventMask = (1 << CGEventType.scrollWheel.rawValue)
                      | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let mySelf = Unmanaged<MacUtilities>.fromOpaque(refcon).takeUnretainedValue()
                return mySelf.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            fputs("Failed to create event tap (permission not ready yet).\n", stderr)
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Event yönlendirme
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .flagsChanged:
            ctrlPressed = event.flags.contains(.maskControl)

        case .scrollWheel:
            // Öncelik: Ctrl basılıysa masaüstü değiştir, olayı yut.
            if ctrlPressed {
                handleDesktopSwitch(event)
                return nil
            }
            // Aksi halde: ScrollFix (fareyse ters çevir).
            applyScrollFix(event)

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Sistem tap'i devre dışı bırakırsa yeniden etkinleştir.
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Feature 1: Desktop Switcher
    private enum Direction { case left, right }

    private func handleDesktopSwitch(_ event: CGEvent) {
        let scrollDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let now = CACurrentMediaTime()
        guard now - lastScrollTime > scrollCooldown else { return }
        guard scrollDelta != 0 else { return }

        switchDesktop(direction: scrollDelta > 0 ? .left : .right)
        lastScrollTime = now
    }

    private func switchDesktop(direction: Direction) {
        let keyCode: CGKeyCode = direction == .left ? 123 : 124 // Sol / Sağ ok
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

    // MARK: - Feature 2: ScrollFix
    // Natural Scrolling sistemde AÇIK varsayımı: trackpad doğal kalsın,
    // klasik fare tekerleği ters çevrilsin. Kaynak ayrımı için scroll olayının
    // "continuous" alanı kullanılır (çentikli fare = false, trackpad = true) —
    // böylece Input Monitoring iznine gerek kalmaz.
    private func applyScrollFix(_ event: CGEvent) {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !isContinuous else { return } // trackpad: dokunma

        let dY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let dX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -dY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -dX)
    }

    // MARK: - Sinyaller
    private func setupSignalHandler() {
        signal(SIGINT)  { _ in NSApp.terminate(nil) }
        signal(SIGTERM) { _ in NSApp.terminate(nil) }
    }
}

// MARK: - Giriş noktası
final class MacUtilitiesApp: NSApplication {
    let utilities = MacUtilities()
    override func run() {
        utilities.start()
        super.run()
    }
}

let app = MacUtilitiesApp.shared
app.setActivationPolicy(.accessory) // Dock'ta görünme
app.run()

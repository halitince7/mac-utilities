import Cocoa

/// Turns a notched mouse wheel's chunky, line-by-line jumps into an animated,
/// pixel-based glide — much closer to a trackpad's smoothness. Each physical
/// notch is consumed and re-emitted as a short ease-out burst of small pixel
/// scrolls.
///
/// Note: this is animated *smoothing*, not trackpad *momentum*. A wheel has no
/// "release" gesture, so there is no inertial flick — every notch glides and
/// settles. Rapid notches accumulate into a longer, smoother glide.
final class SmoothScroller {
    // Tag posted events so our own tap skips them (prevents infinite recursion).
    static let syntheticTag: Int64 = 0x5343524C // "SCRL"

    private let source = CGEventSource(stateID: .hidSystemState)
    private var timer: Timer?
    private var remainingY = 0.0
    private var remainingX = 0.0

    // Tuning.
    private let pixelsPerLine = 48.0     // travel distance per wheel notch
    private let decay = 0.22             // fraction of remaining distance per tick
    private let tickInterval = 1.0 / 120.0

    /// True if the event was synthesized by us (should pass through untouched).
    func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag
    }

    /// Queue a wheel notch. Line deltas are already sign-corrected for the
    /// desired final direction.
    func enqueue(lineDeltaY: Double, lineDeltaX: Double) {
        remainingY += lineDeltaY * pixelsPerLine
        remainingX += lineDeltaX * pixelsPerLine
        startTimer()
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let sy = step(&remainingY)
        let sx = step(&remainingX)
        if sy == 0 && sx == 0 {
            timer?.invalidate(); timer = nil
            return
        }
        guard let event = CGEvent(scrollWheelEvent2Source: source,
                                  units: .pixel, wheelCount: 2,
                                  wheel1: sy, wheel2: sx, wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        event.post(tap: .cgSessionEventTap)
    }

    /// Ease-out: consume a fraction of the remaining distance each tick (at
    /// least 1px), finishing the small tail exactly so it settles cleanly.
    private func step(_ remaining: inout Double) -> Int32 {
        if remaining == 0 { return 0 }
        var s = remaining * decay
        if abs(s) < 1 { s = remaining }             // finish the tail in one step
        var px = Int32(s.rounded())
        if px == 0 { px = remaining > 0 ? 1 : -1 }  // guarantee progress
        remaining -= Double(px)
        if abs(remaining) < 0.5 { remaining = 0 }
        return px
    }
}

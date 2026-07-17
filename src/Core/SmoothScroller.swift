import Cocoa
import CoreVideo

/// Turns a notched mouse wheel's chunky, line-by-line jumps into an animated,
/// pixel-based glide — much closer to a trackpad's smoothness.
///
/// Fluidity comes from three things:
///   1. A CVDisplayLink drives updates in sync with the display refresh (VSync),
///      so there's no timer jitter.
///   2. A time-constant ease-out (framerate-independent) gives a natural glide.
///   3. Sub-pixel carry keeps slow, tail-end motion perfectly smooth.
///
/// Note: this is animated *smoothing*, not trackpad *momentum*. A wheel has no
/// "release" gesture, so there's no inertial flick — each notch glides and
/// settles; rapid notches accumulate into a longer glide.
final class SmoothScroller {
    // Tag posted events so our own tap skips them (prevents infinite recursion).
    static let syntheticTag: Int64 = 0x5343524C // "SCRL"

    private let source = CGEventSource(stateID: .hidSystemState)
    private var link: CVDisplayLink?
    private let lock = NSLock()

    private var remainingY = 0.0     // distance left to travel (points)
    private var remainingX = 0.0
    private var carryY = 0.0         // sub-pixel remainder not yet emitted
    private var carryX = 0.0
    private var lastTime = 0.0

    // Tuning.
    private let pixelsPerLine = 58.0 // travel distance per wheel notch
    private let tau = 0.085          // smoothing time constant — bigger = longer, silkier glide

    init() {
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link = link else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { (_, inNow, _, _, _, ctx) -> CVReturn in
            Unmanaged<SmoothScroller>.fromOpaque(ctx!).takeUnretainedValue().frame(inNow.pointee)
            return kCVReturnSuccess
        }, ctx)
    }

    deinit {
        if let link = link { CVDisplayLinkStop(link) }
    }

    /// True if the event was synthesized by us (should pass through untouched).
    func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag
    }

    /// Queue a wheel notch. Line deltas are already sign-corrected for the
    /// desired final direction.
    func enqueue(lineDeltaY: Double, lineDeltaX: Double) {
        lock.lock()
        remainingY += lineDeltaY * pixelsPerLine
        remainingX += lineDeltaX * pixelsPerLine
        lock.unlock()

        if let link = link, !CVDisplayLinkIsRunning(link) {
            lastTime = 0
            CVDisplayLinkStart(link)
        }
    }

    private func frame(_ now: CVTimeStamp) {
        let t = Double(now.videoTime) / Double(now.videoTimeScale)

        lock.lock()
        // Framerate-independent step size via an exponential time constant.
        let dt = lastTime == 0 ? 1.0 / 60.0 : max(1.0 / 240.0, min(0.05, t - lastTime))
        lastTime = t
        let factor = 1 - exp(-dt / tau)

        let moveY = remainingY * factor
        let moveX = remainingX * factor
        remainingY -= moveY
        remainingX -= moveX
        if abs(remainingY) < 0.1 { remainingY = 0 }
        if abs(remainingX) < 0.1 { remainingX = 0 }

        // Sub-pixel carry: emit whole pixels, keep the fraction for next frame.
        let totalY = moveY + carryY
        let totalX = moveX + carryX
        let pxY = Int32(totalY.rounded(.towardZero))
        let pxX = Int32(totalX.rounded(.towardZero))
        carryY = totalY - Double(pxY)
        carryX = totalX - Double(pxX)

        let idle = remainingY == 0 && remainingX == 0
        lock.unlock()

        if pxY != 0 || pxX != 0 {
            if let event = CGEvent(scrollWheelEvent2Source: source,
                                   units: .pixel, wheelCount: 2,
                                   wheel1: pxY, wheel2: pxX, wheel3: 0) {
                event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
                event.post(tap: .cgSessionEventTap)
            }
        }

        if idle { stopWhenIdle() }
    }

    /// Stop the display link once there's nothing left to animate. Done off the
    /// callback thread, and re-checked so a fresh notch doesn't get cut off.
    private func stopWhenIdle() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let link = self.link else { return }
            self.lock.lock()
            let stillIdle = self.remainingY == 0 && self.remainingX == 0
            self.lock.unlock()
            if stillIdle && CVDisplayLinkIsRunning(link) {
                CVDisplayLinkStop(link)
                self.carryY = 0; self.carryX = 0
            }
        }
    }
}

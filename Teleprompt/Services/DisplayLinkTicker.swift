import Combine
import QuartzCore
import UIKit

struct DisplayFrame: Equatable {
    let sequence: UInt64
    let elapsed: TimeInterval
}

/// Delivers frames on the display's refresh cycle instead of relying on a
/// run-loop timer. `targetTimestamp` also lets scrolling use real elapsed time
/// when iOS changes the refresh rate or briefly delays a frame.
final class DisplayLinkTicker: NSObject, ObservableObject {
    @Published private(set) var frame: DisplayFrame?

    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var sequence: UInt64 = 0

    func start() {
        guard displayLink == nil else { return }

        let newDisplayLink = CADisplayLink(
            target: self,
            selector: #selector(displayLinkDidFire(_:))
        )
        if #available(iOS 15.0, *) {
            let maximumRefreshRate = Float(UIScreen.main.maximumFramesPerSecond)
            newDisplayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(30, maximumRefreshRate),
                maximum: maximumRefreshRate,
                preferred: 0
            )
        }
        newDisplayLink.add(to: .main, forMode: .common)
        displayLink = newDisplayLink
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
    }

    @objc private func displayLinkDidFire(_ displayLink: CADisplayLink) {
        let timestamp = displayLink.targetTimestamp
        defer { previousTimestamp = timestamp }

        guard let previousTimestamp else { return }

        // Do not make the script jump ahead after a long interruption (for
        // example, when Control Center is briefly shown).
        let elapsed = min(1.0 / 12.0, max(0, timestamp - previousTimestamp))
        guard elapsed > 0 else { return }

        sequence &+= 1
        frame = DisplayFrame(sequence: sequence, elapsed: elapsed)
    }

    deinit {
        displayLink?.invalidate()
    }
}

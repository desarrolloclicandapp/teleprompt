import Foundation

enum ReaderScrollMotion {
    static func automaticDistance(
        speed: Double,
        fontScale: Double,
        elapsed: TimeInterval
    ) -> CGFloat {
        distance(
            speed: speed,
            multiplier: 0.12,
            fontScale: fontScale,
            elapsed: elapsed
        )
    }

    static func joystickDistance(
        input: Double,
        speed: Double,
        fontScale: Double,
        elapsed: TimeInterval
    ) -> CGFloat {
        distance(
            speed: input * speed,
            multiplier: 0.18,
            fontScale: fontScale,
            elapsed: elapsed
        )
    }

    private static func distance(
        speed: Double,
        multiplier: Double,
        fontScale: Double,
        elapsed: TimeInterval
    ) -> CGFloat {
        guard speed.isFinite,
              fontScale.isFinite,
              elapsed.isFinite,
              elapsed > 0 else {
            return 0
        }

        return CGFloat(speed * multiplier * fontScale * elapsed)
    }
}

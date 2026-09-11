import Foundation

enum FoldMath {
    static let minimumAngle = 45.0
    static func clamp(_ x: Double, _ low: Double = 0, _ high: Double = 1) -> Double {
        min(high, max(low, x))
    }
    static func smoothstep(_ x: Double) -> Double {
        let t = clamp(x)
        return t * t * (3 - 2 * t)
    }
    static func openness(angle: Double, fullAngle: Double) -> Double {
        clamp((angle - minimumAngle) / (max(65, fullAngle) - minimumAngle))
    }
    // The observer is fixed above the keyboard, at the original top's world
    // height. This keeps that top at the same perceived height while rotating.
    static func referenceUV(u: Double, v: Double, angle: Double, fullAngle: Double,
                            eyeHeight: Double? = nil, eyeDistance: Double = 2.4) -> (Double, Double) {
        let delta = (fullAngle - clamp(angle, minimumAngle, fullAngle)) * .pi / 180
        let full = fullAngle * .pi / 180
        let worldHeight = eyeHeight ?? sin(full)
        let eyeY = eyeDistance * cos(full) + worldHeight * sin(full)
        let eyeZ = eyeDistance * sin(full) - worldHeight * cos(full)
        let height = 1 - v
        let depth = eyeZ / (eyeZ - height * sin(delta))
        return (0.5 + (u - 0.5) * depth,
                1 - (eyeY + (height * cos(delta) - eyeY) * depth))
    }
    static func decodeReport(_ bytes: [UInt8], length: Int) -> Double? {
        guard length >= 3, bytes.count >= 3, bytes[0] == 1 else { return nil }
        let value = Int(bytes[1]) | (Int(bytes[2]) << 8)
        return (0...180).contains(value) ? Double(value) : nil
    }
    static func approach(_ current: Double, _ target: Double, dt: Double) -> Double {
        current + (target - current) * (1 - exp(-max(0, dt) / 0.045))
    }
}

struct FoldState {
    var fullAngle = 135.0
    var enabled = true
    var angle: Double?
    var lastSampleTime: Double?
    var displayed = 1.0
    var previewStart: Double?
    var wakeStart: Double?

    mutating func sample(_ value: Double?, at time: Double) {
        guard let value, value.isFinite, (0...180).contains(value) else { return }
        angle = value
        lastSampleTime = time
    }

    mutating func update(at time: Double, dt: Double) -> Double {
        guard enabled else { displayed = 1; return 1 }
        var target = 1.0
        if let start = previewStart {
            let elapsed = time - start
            if elapsed < 0.8 { target = 1 - FoldMath.smoothstep(elapsed / 0.8) * 0.96 }
            else if elapsed < 1.2 { target = 0.04 }
            else if elapsed < 3.0 { target = 0.04 + 0.96 * FoldMath.smoothstep((elapsed - 1.2) / 1.8) }
            else { previewStart = nil }
        } else if let angle, let lastSampleTime, time - lastSampleTime < 0.65 {
            target = FoldMath.openness(angle: angle, fullAngle: fullAngle)
        }
        if let start = wakeStart {
            if time - start < 0.85 {
                target = min(target, FoldMath.smoothstep((time - start) / 0.85))
            } else { wakeStart = nil }
        }
        displayed = FoldMath.approach(displayed, target, dt: dt)
        if abs(displayed - target) < 0.0005 { displayed = target }
        return displayed
    }
}

import Foundation

var count = 0
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fputs("FAIL: \(description)\n", stderr); exit(1) }
    count += 1
}
check(FoldMath.decodeReport([1, 119, 0], length: 3) == 119, "live sensor report")
check(FoldMath.decodeReport([1, 0, 0], length: 3) == 0, "closed sensor report")
check(FoldMath.decodeReport([1, 180, 0], length: 3) == 180, "upper valid angle")
check(FoldMath.decodeReport([1, 255, 255], length: 3) == nil, "reject corrupt angle")
check(FoldMath.decodeReport([1, 119, 0], length: 2) == nil, "reject short report")
check(FoldMath.decodeReport([2, 119, 0], length: 3) == nil, "reject wrong report ID")
check(FoldMath.decodeReport([], length: 3) == nil, "reject empty report")
check(FoldMath.openness(angle: 0, fullAngle: 119) == 0, "closed maps to zero")
check(FoldMath.openness(angle: 45, fullAngle: 135) == 0, "45 degrees is the closed animation endpoint")
check(FoldMath.openness(angle: 30, fullAngle: 135) == 0, "below 45 does not extend animation")
check(FoldMath.openness(angle: 90, fullAngle: 135) == 0.5, "90 degrees is halfway through requested interval")
check(FoldMath.openness(angle: 135, fullAngle: 135) == 1, "maximum opening restores desktop")
check(FoldMath.openness(angle: 119, fullAngle: 119) == 1, "calibrated maps to one")
check(FoldMath.openness(angle: 140, fullAngle: 119) == 1, "never force beyond normal lid range")
check(FoldMath.openness(angle: 30, fullAngle: 0).isFinite, "invalid calibration remains finite")
for (u, v) in [(0.0, 0.0), (0.3, 0.7), (1.0, 1.0)] {
    let q = FoldMath.referenceUV(u: u, v: v, angle: 135, fullAngle: 135)
    check(abs(q.0 - u) < 1e-9 && abs(q.1 - v) < 1e-9, "projection is identity at original angle")
}
let hinge = FoldMath.referenceUV(u: 0.2, v: 1, angle: 75, fullAngle: 135)
check(abs(hinge.0 - 0.2) < 1e-9 && hinge.1 == 1, "hinge line stays fixed")
// A point on the rotating panel and its mapped desktop point must share
// the SAME sight line from the observer, including the vertical component.
let u = 0.65, v = 0.25, delta = Double.pi / 4
let q = FoldMath.referenceUV(u: u, v: v, angle: 90, fullAngle: 135)
let panelY = (1 - v) * cos(delta), panelZ = (1 - v) * sin(delta)
let full = 135.0 * .pi / 180
let eyeY = 2.4 * cos(full) + sin(full) * sin(full)
let eyeZ = 2.4 * sin(full) - sin(full) * cos(full)
let viewX = (u - 0.5) / (eyeZ - panelZ)
let viewY = (panelY - eyeY) / (eyeZ - panelZ)
check(abs(viewX - (q.0 - 0.5) / eyeZ) < 1e-9, "horizontal viewpoint cancels physical screen motion")
check(abs(viewY - (1 - q.1 - eyeY) / eyeZ) < 1e-9, "vertical viewpoint cancels physical screen motion")
for maximum in [65.0, 90, 120.44032636518772, 135] {
    for angle in stride(from: 45.0, through: maximum, by: 1) {
        // A horizontal sight line through the virtual top has constant world
        // height. It may be clipped by the physical panel, never fit/stretched.
        let physicalHeight = sin(maximum * .pi / 180) / sin(angle * .pi / 180)
        let top = FoldMath.referenceUV(u: 0.5, v: 1 - physicalHeight, angle: angle, fullAngle: maximum)
        check(abs(top.1) < 1e-9, "virtual top stays at maximum opening world height")
        for h in [0.0, 0.25, 0.5, 0.75, 1] {
            let uv = FoldMath.referenceUV(u: 0.2, v: 1 - h, angle: angle, fullAngle: maximum)
            check(uv.0.isFinite && uv.1.isFinite, "projection stays finite throughout supported range")
        }
    }
}
let aboveTop = FoldMath.referenceUV(u: 0.5, v: 0, angle: 90, fullAngle: 120)
check(aboveTop.1 < 0, "physical top becomes black above virtual desktop instead of stretching")
var state = FoldState()
state.sample(40, at: 0)
for i in 1...30 { _ = state.update(at: Double(i) / 60, dt: 1.0 / 60) }
check(state.displayed < 0.4, "follows partial closure")
for i in 31...100 { _ = state.update(at: Double(i) / 60, dt: 1.0 / 60) }
check(state.displayed == 1, "stale sensor fails open instead of obscuring desktop")
state.sample(.nan, at: 2)
check(state.lastSampleTime == 0, "NaN does not refresh liveness")
state.sample(181, at: 2)
check(state.lastSampleTime == 0, "out of range does not refresh liveness")
state.enabled = false; state.displayed = 0; state.previewStart = 2
check(state.update(at: 2.5, dt: 0.016) == 1, "pause clears active animation immediately")
state = FoldState(); state.previewStart = 0
for i in 1...240 { _ = state.update(at: Double(i) / 60, dt: 1.0 / 60) }
check(state.previewStart == nil && state.displayed == 1, "preview restores desktop and exits")
state = FoldState(); state.wakeStart = 0; state.displayed = 0
for i in 1...120 { _ = state.update(at: Double(i) / 60, dt: 1.0 / 60) }
check(state.wakeStart == nil && state.displayed == 1, "wake animation completes without sensor")
var smoothed = 0.0
for _ in 0..<100 {
    smoothed = FoldMath.approach(smoothed, 1, dt: 1.0 / 60)
    check(smoothed >= 0 && smoothed <= 1, "smoothing never overshoots")
}
print("PASS: \(count) checks (sensor decoding, calibration, stale data, pause, preview, wake, smoothing)")

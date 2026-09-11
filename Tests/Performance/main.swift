import AppKit
import MetalKit

// Full-screen, synthetic, 60 Hz source updates with independently animated
// geometry. Measures native drawing callbacks, not physical scanout times.
final class Benchmark: NSObject {
    let renderer: FoldRenderer
    let overlay: FoldOverlay
    let buffer: CVPixelBuffer
    var link: CADisplayLink!
    var start = CACurrentMediaTime()
    var lastSource = 0.0
    var draws: [Double] = []
    var renders: [Double] = []
    var gpu: [Double] = []
    init(shader: String) throws {
        renderer = try FoldRenderer(shaderURL: URL(fileURLWithPath: shader))
        overlay = FoldOverlay(renderer: renderer)
        var raw: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 1512, 982, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &raw)
        buffer = raw!
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer)!, 200, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        super.init()
        overlay.frameView.onDraw = { [unowned self] in
            renderer.markPresented()
            let now = CACurrentMediaTime()
            if now > start + 1 {
                draws.append(now)
                renders.append(renderer.lastRenderMilliseconds)
                gpu.append(renderer.lastGPUMilliseconds)
            }
        }
        link = overlay.panel.screen!.displayLink(target: self, selector: #selector(frame(_:)))
        let rate = Float(min(120, overlay.panel.screen!.maximumFramesPerSecond))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, rate), maximum: rate, preferred: rate)
        link.add(to: .main, forMode: .common)
    }
    @objc func frame(_ sender: CADisplayLink) {
        let now = CACurrentMediaTime()
        if now - lastSource >= 1.0 / 60 - 0.001 {
            renderer.accept(buffer); lastSource = now
        }
        overlay.show(openness: 0.5 + 0.4 * sin((now - start) * 2), useDesktop: true)
    }
    func finish() {
        link.invalidate()
        let gaps = zip(draws.dropFirst(), draws).map { ($0 - $1) * 1000 }
        func percentile(_ values: [Double], _ quantile: Double) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * quantile))]
        }
        let fps = draws.count > 1 ? Double(draws.count - 1) / (draws.last! - draws.first!) : 0
        let values: [String: Any] = [
            "sourceWidth": 1512, "sourceHeight": 982, "drawnFrames": draws.count,
            "nativeDrawFPS": fps, "frameGapP50ms": percentile(gaps, 0.5), "frameGapP95ms": percentile(gaps, 0.95),
            "renderP50ms": percentile(renders, 0.5), "renderP95ms": percentile(renders, 0.95),
            "gpuP50ms": percentile(gpu, 0.5), "gpuP95ms": percentile(gpu, 0.95),
            "gpuError": renderer.lastGPUError as Any? ?? NSNull()]
        let data = try! JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted])
        print(String(data: data, encoding: .utf8)!)
        overlay.hide(); fflush(stdout)
        exit(fps > 50 && renderer.lastGPUError == nil ? 0 : 1)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let shader = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath + "/Resources/Fold.metal"
let benchmark = try Benchmark(shader: shader)
DispatchQueue.main.asyncAfter(deadline: .now() + 6) { benchmark.finish() }
app.run()

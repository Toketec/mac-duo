import AppKit
import MetalKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let renderer = try FoldRenderer(shaderURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Resources/Fold.metal"))
let overlay = FoldOverlay(renderer: renderer)
var buffer: CVPixelBuffer?
let result = CVPixelBufferCreate(kCFAllocatorDefault, 320, 200, kCVPixelFormatType_32BGRA,
    [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
guard result == kCVReturnSuccess, let buffer else { fatalError("Synthetic buffer unavailable") }
CVPixelBufferLockBaseAddress(buffer, [])
memset(CVPixelBufferGetBaseAddress(buffer)!, 200, CVPixelBufferGetDataSize(buffer))
CVPixelBufferUnlockBaseAddress(buffer, [])
renderer.accept(buffer)
renderer.fullAngle = 120
// Exercise the actual window, CVPixelBuffer, GPU pipeline, and AppKit drawing.
// No desktop capture or screen recording permission is used by this test.
overlay.panel.setFrame(NSRect(x: 60, y: 60, width: 640, height: 400), display: true)
overlay.show(openness: 0.6, useDesktop: true)
let start = CACurrentMediaTime()
var held: CGImage?
var heldBytes: Data?
var stationaryFrames = 0
func pixels(_ image: CGImage) -> Data {
    let data = image.dataProvider!.data!
    return Data(bytes: CFDataGetBytePtr(data)!, count: CFDataGetLength(data))
}
let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
    let elapsed = CACurrentMediaTime() - start
    if elapsed > 0.2 && held == nil, let image = overlay.frameView.image {
        held = image; heldBytes = pixels(image)
        let bytes = heldBytes!
        let top = image.width / 2 * 4
        let inside = image.bytesPerRow * (image.height * 3 / 4) + top
        guard bytes[top] == 0 && bytes[top + 1] == 0 && bytes[top + 2] == 0,
              bytes[inside] > 50 else { fatalError("GPU must leave black above the bounded virtual desktop") }
    }
    let openness = elapsed < 0.25 ? 0.6 : (elapsed < 1.1 ? 0.6 + 0.2 * sin(elapsed * 7) : 0.6)
    overlay.show(openness: openness, useDesktop: true)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
    overlay.hide()
    overlay.show(openness: 0.6, useDesktop: true)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { stationaryFrames = renderer.completedFrames }
RunLoop.main.add(timer, forMode: .common)
DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    let passed = (overlay.frameView.layer?.contentsScale ?? 0) >= 1
        && overlay.frameView.image != nil && renderer.presentedFrames > 0
        && renderer.completedFrames > 10 && renderer.lastGPUError == nil
        && held.map { pixels($0) == heldBytes } == true
        && renderer.completedFrames == stationaryFrames
    print("submitted", renderer.submittedFrames, "completed", renderer.completedFrames,
          "drawn by AppKit", renderer.presentedFrames, "GPU error", renderer.lastGPUError ?? "none")
    print(overlay.diagnosticValues)
    timer.invalidate(); overlay.hide()
    print(passed ? "PASS: native drawing, bounded top, immutable retained frames, hide/reopen, stationary cache" : "FAIL: native window presentation")
    fflush(stdout); exit(passed ? 0 : 1)
}
app.run()

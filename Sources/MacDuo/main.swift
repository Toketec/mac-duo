import AppKit
import MetalKit

let arguments = CommandLine.arguments
if arguments.contains("--diagnose") {
    let sensor = LidSensor()
    let (angle, status) = sensor.readOnce()
    let renderer = try FoldRenderer(shaderURL: shaderURL())
    let builtIn = NSScreen.screens.contains {
        guard let n = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(n.uint32Value) != 0
    }
    let values: [String: Any] = ["angle": angle as Any? ?? NSNull(), "sensor": status,
                                "screenCaptureAuthorized": CGPreflightScreenCaptureAccess(),
                                "builtInScreen": builtIn, "metalDevice": renderer.device.name,
                                "shaderCompiled": true]
    let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} else if let index = arguments.firstIndex(of: "--render-previews"), arguments.count > index + 1 {
    _ = NSApplication.shared
    let directory = URL(fileURLWithPath: arguments[index + 1])
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let renderer = try FoldRenderer(shaderURL: shaderURL())
    let size = NSSize(width: 1000, height: 650)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGradient(colors: [NSColor(calibratedRed: 0.22, green: 0.34, blue: 0.83, alpha: 1),
                        NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.78, alpha: 1),
                        NSColor(calibratedRed: 0.94, green: 0.64, blue: 0.59, alpha: 1)])?.draw(in: NSRect(origin: .zero, size: size), angle: 25)
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: 160, y: 140, width: 680, height: 400), xRadius: 18, yRadius: 18).fill()
    ("Mac Duo" as NSString).draw(at: NSPoint(x: 208, y: 443), withAttributes: [.font: NSFont.systemFont(ofSize: 32, weight: .semibold), .foregroundColor: NSColor.black])
    ("开合之间，清晰浮现。" as NSString).draw(at: NSPoint(x: 210, y: 405), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.darkGray])
    for row in 0..<4 {
        NSColor(calibratedWhite: 0.8, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 212, y: 340 - row * 39, width: 370 + (row % 2) * 160, height: 12), xRadius: 6, yRadius: 6).fill()
    }
    image.unlockFocus()
    let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    var sweep: [Float] = [0, 0.25, 0.5, 0.75, 1]
    var dense = false
    if let index = arguments.firstIndex(of: "--sweep"), arguments.count > index + 1,
       let count = Int(arguments[index + 1]), count >= 2, count <= 240 {
        dense = true
        sweep = (0..<count).map { Float($0) / Float(count - 1) }
    }
    for p in sweep {
        let name = dense ? String(format: "fold-%03d.png", Int((p * 100).rounded()))
                         : "fold-\(Int(p * 100)).png"
        try renderer.renderTestFrame(image: cg, openness: p, to: directory.appendingPathComponent(name))
    }
    let controls = ControlPanel()
    _ = controls.view
    controls.update(angle: 90, openness: 0.5, status: "实时铰链已连接", fullAngle: 135, enabled: true, capture: true)
    let window = NSWindow(contentRect: controls.view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = controls.view
    for name in ["normal", "pressed", "unchecked"] {
        controls.toggle.state = name == "unchecked" ? .off : .on
        for button in controls.view.subviews.compactMap({ $0 as? PanelButton }) {
            button.highlight(name == "pressed")
        }
        controls.view.layoutSubtreeIfNeeded()
        let bitmap = controls.view.bitmapImageRepForCachingDisplay(in: controls.view.bounds)!
        controls.view.cacheDisplay(in: controls.view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("panel-\(name).png"))
    }
    print("Rendered \(sweep.count) Gaussian/Metal frames and 3 panel states to \(directory.path)")
} else {
    let app = NSApplication.shared
    // Opening the app again brings up the existing instance instead of
    // creating a second overlay and competing for the global hotkey.
    if let id = Bundle.main.bundleIdentifier,
       NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
           $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
       }) { exit(0) }
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

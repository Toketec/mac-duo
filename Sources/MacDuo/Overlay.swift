import AppKit

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DesktopFrameView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    var onDraw: (() -> Void)?
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
        if let image {
            context.interpolationQuality = .high
            context.draw(image, in: bounds)
            onDraw?()
        }
    }
}

final class FoldOverlay {
    let panel: OverlayPanel
    let renderer: FoldRenderer
    let frameView = DesktopFrameView()
    private let blur = NSVisualEffectView()
    private let shade = CALayer()
    private var visible = false
    private var wantsDesktop = false
    var displayID: CGDirectDisplayID?

    init(renderer: FoldRenderer) {
        self.renderer = renderer
        panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        let root = NSView()
        root.wantsLayer = true
        panel.contentView = root
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        root.addSubview(blur)
        shade.backgroundColor = NSColor.black.cgColor
        root.layer?.addSublayer(shade)
        frameView.wantsLayer = true
        frameView.autoresizingMask = [.width, .height]
        frameView.onDraw = { [weak renderer] in renderer?.markPresented() }
        root.addSubview(frameView)
        refreshScreen()
    }

    func refreshScreen() {
        hide()
        guard let screen = NSScreen.screens.first(where: {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }), let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            displayID = nil
            return
        }
        displayID = number.uint32Value
        panel.setFrame(screen.frame, display: true)
        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        blur.frame = bounds; shade.frame = bounds; frameView.frame = bounds
        frameView.layer?.contentsScale = screen.backingScaleFactor
    }

    func show(openness: Double, useDesktop: Bool) {
        guard displayID != nil else { hide(); return }
        wantsDesktop = useDesktop
        let amount = 1 - FoldMath.smoothstep(openness)
        renderer.openness = Float(openness)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if useDesktop && renderer.hasFrame && frameView.image != nil {
            frameView.isHidden = false
            blur.isHidden = true; shade.opacity = 0
            panel.alphaValue = min(1, (1 - openness) / 0.035)
        } else {
            frameView.isHidden = true
            blur.isHidden = false; blur.alphaValue = amount
            shade.opacity = Float(amount * 0.92); panel.alphaValue = 1
        }
        CATransaction.commit()
        if !visible { panel.orderFrontRegardless(); visible = true }
        if useDesktop && renderer.hasFrame {
            renderer.renderForDisplay { [weak self] image in
                guard let self, self.visible, self.wantsDesktop else { return }
                self.frameView.image = image
                self.frameView.isHidden = false
                self.blur.isHidden = true
                self.shade.opacity = 0
            }
        }
    }

    func hide() {
        guard visible else { return }
        panel.orderOut(nil)
        visible = false; wantsDesktop = false
        frameView.image = nil
        renderer.invalidateDisplay()
    }

    var diagnosticValues: [String: Any] {
        ["presentationBackend": "AppKit + Metal",
         "displayContentsScale": frameView.layer?.contentsScale ?? 0,
         "displayWidth": frameView.bounds.width, "displayHeight": frameView.bounds.height,
         "displayHidden": frameView.isHidden, "displayImageReady": frameView.image != nil,
         "windowAlpha": panel.alphaValue]
    }
}

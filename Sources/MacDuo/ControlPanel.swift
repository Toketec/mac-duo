import AppKit

// Opaque backing and explicit button colors stay legible when the popover
// becomes key. They do not inherit an active Liquid Glass backdrop tint.
final class PanelBackground: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.095, green: 0.105, blue: 0.135, alpha: 1).setFill()
        bounds.fill()
    }
}

final class PanelButton: NSButton {
    var prominent = false
    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor
        if prominent {
            fill = isHighlighted ? NSColor(calibratedRed: 0.31, green: 0.32, blue: 0.67, alpha: 1)
                                 : NSColor(calibratedRed: 0.40, green: 0.42, blue: 0.85, alpha: 1)
        } else {
            fill = NSColor(calibratedWhite: isHighlighted ? 0.32 : 0.21, alpha: 1)
        }
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 7, yRadius: 7)
        fill.setFill(); outline.fill()
        NSColor.white.withAlphaComponent(0.15).setStroke(); outline.lineWidth = 1; outline.stroke()
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke(); outline.lineWidth = 2; outline.stroke()
        }
        let color = NSColor(calibratedWhite: isEnabled ? 1 : 0.65, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: color]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

final class HingeIllustration: NSView {
    var openness = 1.0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        NSColor(calibratedRed: 0.075, green: 0.09, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
        let w = r.width * 0.70, h = r.height * 0.66
        let x = r.midX - w / 2, y = r.minY + 22
        let inset = CGFloat(1 - openness) * 27
        let screen = NSBezierPath()
        screen.move(to: NSPoint(x: x, y: y))
        screen.line(to: NSPoint(x: x + w, y: y))
        screen.line(to: NSPoint(x: x + w - inset, y: y + h))
        screen.line(to: NSPoint(x: x + inset, y: y + h))
        screen.close()
        NSGraphicsContext.saveGraphicsState()
        screen.addClip()
        NSGradient(colors: [NSColor(calibratedRed: 0.29, green: 0.48, blue: 0.98, alpha: 1),
                            NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.88, alpha: 1),
                            NSColor(calibratedRed: 0.94, green: 0.66, blue: 0.65, alpha: 1)])?.draw(in: screen, angle: 35)
        NSGradient(starting: .clear, ending: NSColor.black.withAlphaComponent(1 - openness))?.draw(in: screen, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.30).setStroke(); screen.lineWidth = 1; screen.stroke()
        NSColor(calibratedWhite: 0.55, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 12, y: y - 7, width: w + 24, height: 5), xRadius: 3, yRadius: 3).fill()
    }
}

final class ControlPanel: NSViewController {
    let angleLabel = NSTextField(labelWithString: "—°")
    let statusLabel = NSTextField(labelWithString: "正在连接铰链…")
    let detailLabel = NSTextField(wrappingLabelWithString: "")
    let illustration = HingeIllustration()
    let toggle = NSButton(checkboxWithTitle: "跟随 Mac 屏幕开合", target: nil, action: nil)
    let fullLabel = NSTextField(labelWithString: "动画区间 45°–135°")
    let slider = NSSlider(value: 135, minValue: 65, maxValue: 135, target: nil, action: nil)
    let permissionButton = PanelButton(title: "启用真实桌面效果…", target: nil, action: nil)
    var onPreview: (() -> Void)?
    var onToggle: ((Bool) -> Void)?
    var onCalibration: (() -> Void)?
    var onAngle: ((Double) -> Void)?
    var onPermission: (() -> Void)?
    var onQuit: (() -> Void)?

    override func loadView() {
        view = PanelBackground(frame: NSRect(x: 0, y: 0, width: 360, height: 526))
        view.appearance = NSAppearance(named: .darkAqua)
        let title = NSTextField(labelWithString: "Mac Duo")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        put(title, x: 22, y: 480, w: 220, h: 32)
        let sub = NSTextField(labelWithString: "开合之间，清晰浮现。")
        sub.textColor = .secondaryLabelColor
        sub.font = .systemFont(ofSize: 12)
        put(sub, x: 23, y: 457, w: 290, h: 20)
        put(illustration, x: 20, y: 308, w: 320, h: 140)
        angleLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        angleLabel.alignment = .right
        put(angleLabel, x: 242, y: 267, w: 94, h: 31)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        put(statusLabel, x: 24, y: 275, w: 216, h: 18)
        toggle.state = .on; toggle.target = self; toggle.action = #selector(toggleAction)
        toggle.contentTintColor = .white
        put(toggle, x: 22, y: 237, w: 290, h: 24)
        fullLabel.font = .systemFont(ofSize: 12)
        fullLabel.textColor = .secondaryLabelColor
        put(fullLabel, x: 24, y: 209, w: 185, h: 18)
        let calibration = button("以当前角度校准", action: #selector(calibrateAction))
        put(calibration, x: 213, y: 202, w: 125, h: 28)
        slider.isContinuous = true; slider.target = self; slider.action = #selector(sliderAction)
        slider.setAccessibilityLabel("完全展开角度")
        put(slider, x: 21, y: 178, w: 318, h: 24)
        let preview = button("预览展开动画", action: #selector(previewAction))
        preview.prominent = true
        put(preview, x: 20, y: 131, w: 320, h: 34)
        permissionButton.bezelStyle = .rounded; permissionButton.target = self
        permissionButton.action = #selector(permissionAction)
        put(permissionButton, x: 20, y: 91, w: 320, h: 32)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        put(detailLabel, x: 24, y: 47, w: 312, h: 37)
        let shortcut = NSTextField(labelWithString: "⌃⌥⌘D 暂停 / 恢复")
        shortcut.font = .systemFont(ofSize: 10)
        shortcut.textColor = .tertiaryLabelColor
        put(shortcut, x: 24, y: 17, w: 220, h: 17)
        put(button("退出", action: #selector(quitAction)), x: 276, y: 10, w: 65, h: 28)
    }
    private func put(_ v: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        v.frame = NSRect(x: x, y: y, width: w, height: h); view.addSubview(v)
    }
    private func button(_ title: String, action: Selector) -> PanelButton {
        let b = PanelButton(title: title, target: self, action: action); b.bezelStyle = .rounded; return b
    }
    @objc private func previewAction() { onPreview?() }
    @objc private func toggleAction() { onToggle?(toggle.state == .on) }
    @objc private func calibrateAction() { onCalibration?() }
    @objc private func sliderAction() { onAngle?(slider.doubleValue) }
    @objc private func permissionAction() { onPermission?() }
    @objc private func quitAction() { onQuit?() }

    func update(angle: Double?, openness: Double, status: String, fullAngle: Double, enabled: Bool, capture: Bool) {
        angleLabel.stringValue = angle.map { "\(Int($0))°" } ?? "—°"
        statusLabel.stringValue = status
        illustration.openness = openness
        toggle.state = enabled ? .on : .off
        slider.doubleValue = fullAngle
        fullLabel.stringValue = "动画区间 45°–\(Int(fullAngle))°"
        permissionButton.title = capture ? "屏幕录制已授权 ✓" : "启用真实桌面效果…"
        permissionButton.isEnabled = !capture
        detailLabel.stringValue = capture
            ? "45° 以下保持收拢态。展开到上限恢复桌面；控制面板始终保持清晰。"
            : "尚未启用桌面重投影。请授权屏幕录制；当前仅为基础模式。"
    }
}

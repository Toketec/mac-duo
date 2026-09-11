import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sensor = LidSensor()
    private let capture = DesktopCapture()
    private var overlay: FoldOverlay!
    private var renderer: FoldRenderer!
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let controls = ControlPanel()
    private var state = FoldState()
    private var timer: Timer?
    private var displayLink: CADisplayLink?
    private var lastTick = CACurrentMediaTime()
    private var lastUI = 0.0
    private var lastPermissionCheck = 0.0
    private var idleSince = CACurrentMediaTime()
    private var nextCaptureAttempt = 0.0
    private var permission = false
    private var suspended = false
    private var locked = false
    private var sensorStatus = "正在连接铰链…"
    private var calibrated = false
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var lastDiagnostic = 0.0

    private var diagnosticURL: URL {
        if let i = CommandLine.arguments.firstIndex(of: "--status-file"), CommandLine.arguments.count > i + 1 {
            return URL(fileURLWithPath: CommandLine.arguments[i + 1])
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDuo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("status.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            renderer = try FoldRenderer(shaderURL: shaderURL())
            overlay = FoldOverlay(renderer: renderer)
        } catch {
            let alert = NSAlert(); alert.messageText = "Mac Duo 无法启动"
            alert.informativeText = error.localizedDescription; alert.runModal()
            NSApp.terminate(nil); return
        }
        // The new requested range ends at full mechanical opening, instead
        // of the first launch's incidental working angle (previously 119°).
        if !UserDefaults.standard.bool(forKey: "uses45DegreeRange") {
            UserDefaults.standard.set(135.0, forKey: "fullAngle")
            UserDefaults.standard.set(true, forKey: "uses45DegreeRange")
        }
        let saved = UserDefaults.standard.double(forKey: "fullAngle")
        if saved >= 65 && saved <= 135 { state.fullAngle = saved; calibrated = true }
        permission = CGPreflightScreenCaptureAccess()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "macbook", accessibilityDescription: "Mac Duo 屏幕开合效果")
        item.button?.target = self; item.button?.action = #selector(showControls)
        item.button?.toolTip = "Mac Duo · 屏幕开合效果"
        popover.contentViewController = controls
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.behavior = .transient
        _ = controls.view
        controls.onPreview = { [weak self] in self?.preview() }
        controls.onToggle = { [weak self] in self?.setEnabled($0) }
        controls.onCalibration = { [weak self] in
            guard let self, let angle = self.state.angle else { return }
            self.setFullAngle(min(135, max(65, angle)))
        }
        controls.onAngle = { [weak self] in self?.setFullAngle($0) }
        controls.onPermission = { [weak self] in self?.requestCapturePermission() }
        controls.onQuit = { NSApp.terminate(nil) }
        capture.onFrame = { [weak renderer] buffer in renderer?.accept(buffer) }
        capture.onStatus = { [weak self] message in
            NSLog("Mac Duo: %@", message)
            if let self, !self.capture.running { self.renderer.clear() }
        }
        sensor.onSample = { [weak self] angle, message in
            guard let self, !self.suspended else { return }
            self.sensorStatus = message
            self.state.sample(angle, at: CACurrentMediaTime())
            if !self.calibrated, let angle, angle >= 65 {
                self.setFullAngle(min(135, angle))
            }
        }
        registerHotKey()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(waking), name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(waking), name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(locking), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(unlocking), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(locking), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(unlocking), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        sensor.start()
        startFrameClock()
        updateControls()
        if !CommandLine.arguments.contains("--background") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showControls() }
        }
        if CommandLine.arguments.contains("--request-capture"), !permission {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.requestCapturePermission() }
        }
        NSLog("Mac Duo ready. Screen capture permission: %@", permission ? "yes" : "no")
    }

    private func startFrameClock() {
        displayLink?.invalidate(); displayLink = nil
        timer?.invalidate(); timer = nil
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == overlay.displayID
        } ?? NSScreen.main
        if let screen {
            let link = screen.displayLink(target: self, selector: #selector(displayFrame(_:)))
            let rate = Float(min(120, max(30, screen.maximumFramesPerSecond)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, rate), maximum: rate, preferred: rate)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let fallback = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(fallback, forMode: .common); timer = fallback
        }
    }
    @objc private func displayFrame(_ sender: CADisplayLink) { tick() }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.05); lastTick = now
        if suspended { writeDiagnostics(at: now); return }
        let openness = state.update(at: now, dt: dt)
        let moving = state.enabled && openness < 0.999
        renderer.fullAngle = Float(state.fullAngle)
        if moving {
            idleSince = now
            if permission, !capture.running, now > nextCaptureAttempt, let display = overlay.displayID {
                nextCaptureAttempt = now + 3
                capture.start(displayID: display)
            }
            overlay.show(openness: openness, useDesktop: permission)
        } else {
            overlay.hide()
            if now - idleSince > 1.5, capture.running { capture.stop(); renderer.clear() }
        }
        if now - lastPermissionCheck > 1 {
            lastPermissionCheck = now
            let old = permission
            permission = CGPreflightScreenCaptureAccess()
            if old && !permission { capture.stop(); renderer.clear() }
        }
        if now - lastUI > 0.2 {
            lastUI = now
            if popover.isShown { updateControls() }
        }
        writeDiagnostics(at: now)
    }

    private func writeDiagnostics(at now: Double) {
        if now - lastDiagnostic > 1 {
            lastDiagnostic = now
            var values: [String: Any] = ["angle": state.angle as Any? ?? NSNull(), "openness": state.displayed,
                "enabled": state.enabled, "screenCaptureAuthorized": permission,
                "captureRunning": capture.running, "desktopFrameReady": renderer.hasFrame,
                "pid": ProcessInfo.processInfo.processIdentifier,
                "suspended": suspended, "locked": locked,
                "submittedFrames": renderer.submittedFrames, "completedFrames": renderer.completedFrames,
                "presentedFrames": renderer.presentedFrames,
                "sourceWidth": renderer.sourceSize.0, "sourceHeight": renderer.sourceSize.1,
                "renderMilliseconds": renderer.lastRenderMilliseconds,
                "gpuMilliseconds": renderer.lastGPUMilliseconds,
                "frameClock": displayLink == nil ? "timer" : "displayLink",
                "preferredFPS": displayLink?.preferredFrameRateRange.preferred ?? 60,
                "gpuError": renderer.lastGPUError as Any? ?? NSNull(),
                "minimumAngle": FoldMath.minimumAngle, "fullAngle": state.fullAngle,
                "panelVisible": popover.isShown, "overlayVisible": overlay.panel.isVisible,
                "panelAboveOverlay": (controls.view.window?.level.rawValue ?? 0) > overlay.panel.level.rawValue,
                "updatedAt": Date().timeIntervalSince1970]
            values.merge(overlay.diagnosticValues) { _, new in new }
            if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: diagnosticURL, options: .atomic)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { showControls() }
        return true
    }

    @objc func showControls() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        overlay.hide()
        updateControls()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        controls.view.window?.appearance = NSAppearance(named: .darkAqua)
        controls.view.window?.level = NSWindow.Level(rawValue: overlay.panel.level.rawValue + 2)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func updateControls() {
        controls.update(angle: state.angle, openness: state.displayed,
                        status: state.enabled ? sensorStatus : "效果已暂停",
                        fullAngle: state.fullAngle, enabled: state.enabled, capture: permission)
    }
    private func setFullAngle(_ value: Double) {
        state.fullAngle = value; calibrated = true
        UserDefaults.standard.set(value, forKey: "fullAngle")
        updateControls()
    }
    private func setEnabled(_ enabled: Bool) {
        state.enabled = enabled
        state.previewStart = nil; state.wakeStart = nil
        if !enabled { overlay.hide(); capture.stop(); renderer.clear() }
        item.button?.appearsDisabled = !enabled
        updateControls()
    }
    @objc func toggleEffect() { setEnabled(!state.enabled) }
    private func preview() {
        setEnabled(true)
        popover.performClose(nil)
        if permission, let display = overlay.displayID { capture.start(displayID: display) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.state.enabled, !self.suspended else { return }
            self.state.previewStart = CACurrentMediaTime()
        }
    }
    private func requestCapturePermission() {
        popover.performClose(nil)
        if CGPreflightScreenCaptureAccess() { permission = true; return }
        let granted = CGRequestScreenCaptureAccess()
        permission = granted
        if !granted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func sleeping() {
        suspended = true
        popover.performClose(nil)
        state.previewStart = nil; state.wakeStart = nil
        overlay.hide(); capture.stop(); renderer.clear()
        sensor.stop()
    }
    @objc private func waking() {
        guard suspended, !locked else { return }
        suspended = false
        state.lastSampleTime = nil
        state.wakeStart = CACurrentMediaTime()
        state.displayed = 0
        lastTick = CACurrentMediaTime()
        nextCaptureAttempt = 0
        overlay.refreshScreen()
        sensor.start()
    }
    @objc private func locking() { locked = true; sleeping() }
    @objc private func unlocking() { locked = false; waking() }
    @objc private func screenChanged() {
        overlay.refreshScreen(); capture.stop(); renderer.clear(); nextCaptureAttempt = 0
        startFrameClock()
    }
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { app.toggleEffect() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let id = EventHotKeyID(signature: 0x4D44554F, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey | cmdKey), id,
                                        GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { NSLog("Mac Duo: hotkey registration failed: %d", result) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        overlay.hide(); timer?.invalidate(); displayLink?.invalidate(); sensor.stop(); capture.stop()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

func shaderURL() -> URL {
    Bundle.main.url(forResource: "Fold", withExtension: "metal")
        ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Fold.metal")
}

import Foundation
import IOKit.hid

// Apple sensor usage 0x20/0x8A, feature report 1. See THIRD_PARTY_NOTICES.md.
// Read-only: never writes a feature report or changes sensor calibration.
final class LidSensor {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "local.macduo.lid", qos: .userInteractive)
    private var misses = 0
    private var nextConnect = 0.0
    private var previousAngle: Double?
    private var lastMotionAt = 0.0
    private var pollingFast = true
    var onSample: ((Double?, String) -> Void)?

    func readOnce() -> (Double?, String) {
        if device == nil, Date.timeIntervalSinceReferenceDate >= nextConnect {
            disconnect()
            nextConnect = Date.timeIntervalSinceReferenceDate + 1
            connect()
        }
        guard let device else { return (nil, "未连接到铰链传感器") }
        var bytes = [UInt8](repeating: 0, count: 3)
        var length = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length)
        guard result == kIOReturnSuccess,
              let angle = FoldMath.decodeReport(bytes, length: length) else {
            misses += 1
            if misses >= 15 { disconnect() }
            return (nil, "传感器正在重新连接")
        }
        misses = 0
        return (angle, "实时铰链已连接")
    }

    func start() {
        guard timer == nil else { return }
        pollingFast = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let (angle, message) = self.readOnce()
            let now = ProcessInfo.processInfo.systemUptime
            if let angle {
                if let previous = self.previousAngle, abs(angle - previous) >= 0.5 { self.lastMotionAt = now }
                self.previousAngle = angle
            }
            let fast = now - self.lastMotionAt < 1
            if fast != self.pollingFast {
                self.pollingFast = fast
                let interval = DispatchTimeInterval.milliseconds(fast ? 8 : 33)
                self.timer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(2))
            }
            DispatchQueue.main.async { [weak self] in self?.onSample?(angle, message) }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.sync { disconnect() }
    }

    private func connect() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDPrimaryUsagePageKey: 0x20,
            kIOHIDPrimaryUsageKey: 0x8A
        ] as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let found = devices.first,
              IOHIDDeviceOpen(found, 0) == kIOReturnSuccess else { return }
        device = found
    }

    private func disconnect() {
        if let device { IOHIDDeviceClose(device, 0) }
        if let manager { IOHIDManagerClose(manager, 0) }
        device = nil
        manager = nil
        misses = 0
    }
    deinit { if timer == nil { disconnect() } }
}

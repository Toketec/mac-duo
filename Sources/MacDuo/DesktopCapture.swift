import AppKit
import ScreenCaptureKit
import CoreMedia

final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var starting = false
    private var generation = 0
    private let queue = DispatchQueue(label: "local.macduo.capture", qos: .userInteractive)
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onStatus: ((String) -> Void)?
    var running: Bool { stream != nil || starting }

    func start(displayID: CGDirectDisplayID) {
        guard !running, CGPreflightScreenCaptureAccess() else { return }
        starting = true
        generation += 1
        let token = generation
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard token == generation else { return }
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    starting = false
                    onStatus?("内置显示屏暂不可用")
                    return
                }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                // One source pixel per screen point is sufficient during motion
                // blur. At full opening the actual Retina desktop is revealed.
                config.width = display.width
                config.height = display.height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.queueDepth = 3
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                config.capturesAudio = false
                config.colorSpaceName = CGColorSpace.sRGB
                let newStream = SCStream(filter: filter, configuration: config, delegate: self)
                try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                stream = newStream
                try await newStream.startCapture()
                guard token == generation else { try? await newStream.stopCapture(); return }
                starting = false
                onStatus?("桌面折叠已就绪")
            } catch {
                guard token == generation else { return }
                starting = false
                stream = nil
                onStatus?("桌面捕获不可用：\(error.localizedDescription)")
            }
        }
    }

    func stop() {
        generation += 1
        let old = stream
        stream = nil
        starting = false
        if let old { Task { try? await old.stopCapture() } }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.onFrame?(buffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.starting = false
            self.onStatus?("桌面捕获已暂停")
        }
    }
}

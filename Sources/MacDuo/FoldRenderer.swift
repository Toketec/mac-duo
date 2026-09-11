import AppKit
import MetalKit
import CoreVideo
import MetalPerformanceShaders

// A provider keeps its slot leased until Core Graphics releases the image.
// The GPU must never overwrite pixels still being read by AppKit.
private final class DisplayStorage {
    let buffer: MTLBuffer
    let bytesPerRow: Int
    let width: Int
    let height: Int
    private let lock = NSLock()
    private var leased = false
    init?(device: MTLDevice, width: Int, height: Int) {
        self.width = width; self.height = height
        bytesPerRow = (width * 4 + 255) & ~255
        guard let buffer = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared) else { return nil }
        self.buffer = buffer
    }
    func acquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !leased else { return false }
        leased = true; return true
    }
    func release() { lock.lock(); leased = false; lock.unlock() }
}

final class FoldRenderer: NSObject {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache?
    private var gaussianTextures: [MTLTexture] = []
    private var gaussianKernels: [MPSImageGaussianBlur] = []
    private var scaledTextures: [MTLTexture] = []
    private lazy var scaler = MPSImageBilinearScale(device: device)
    private var displayStorage: [DisplayStorage] = []
    private var lastRenderedVersion: UInt64?
    private var lastRenderedSettings: [SIMD4<Float>]?
    private var lastRenderedGeneration = -1
    private(set) var lastRenderMilliseconds = 0.0
    private(set) var lastGPUMilliseconds = 0.0
    private var cachedVersion: UInt64?
    private let displayQueue = DispatchQueue(label: "local.macduo.render", qos: .userInteractive)
    private var rendering = false
    private var outputTexture: MTLTexture?
    private var generation = 0
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var frameVersion: UInt64 = 0
    var openness: Float = 1
    var fullAngle: Float = 135
    var strength: Float = 1
    private(set) var submittedFrames = 0
    private(set) var completedFrames = 0
    private(set) var presentedFrames = 0
    private(set) var lastGPUError: String?
    var sourceSize: (Int, Int) {
        lock.lock(); defer { lock.unlock() }
        guard let latest else { return (0, 0) }
        return (CVPixelBufferGetWidth(latest), CVPixelBufferGetHeight(latest))
    }
    var hasFrame: Bool { lock.lock(); defer { lock.unlock() }; return latest != nil }

    init(shaderURL: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "MacDuo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal GPU 不可用"])
        }
        self.device = device
        self.queue = queue
        let library = try device.makeLibrary(source: String(contentsOf: shaderURL, encoding: .utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
    }

    func accept(_ buffer: CVPixelBuffer) {
        lock.lock(); latest = buffer; frameVersion &+= 1; lock.unlock()
    }
    func clear() { lock.lock(); latest = nil; generation += 1; lock.unlock() }
    func invalidateDisplay() { lock.lock(); generation += 1; lock.unlock() }
    func markPresented() { presentedFrames += 1 }

    // Render in a GPU-private texture and blit to pooled shared storage.
    // CGImage retains that storage directly, with no per-frame CPU copy.
    // AppKit presents the immutable image. This avoids CAMetalLayer drawable presentation on transparent
    // accessory panels, while keeping the projection and blur on the GPU.
    func renderForDisplay(onReady: @escaping (CGImage) -> Void) {
        guard !rendering else { return }
        lock.lock(); let buffer = latest; let version = frameVersion; let token = generation; lock.unlock()
        guard let buffer else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let uniforms = [SIMD4<Float>(openness, fullAngle, Float(width), Float(height)),
                        SIMD4<Float>(strength, sin(fullAngle * .pi / 180), 2.4, 0)]
        guard version != lastRenderedVersion || uniforms != lastRenderedSettings || token != lastRenderedGeneration else { return }
        rendering = true
        let started = CACurrentMediaTime()
        submittedFrames += 1
        displayQueue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.makeDisplayImage(buffer: buffer, version: version, uniforms: uniforms)
                let elapsed = (CACurrentMediaTime() - started) * 1000
                DispatchQueue.main.async {
                    self.rendering = false
                    self.lock.lock(); let current = self.generation; self.lock.unlock()
                    guard current == token else { return }
                    self.lastRenderedVersion = version
                    self.lastRenderedSettings = uniforms
                    self.lastRenderedGeneration = token
                    self.lastRenderMilliseconds = elapsed
                    self.completedFrames += 1
                    self.lastGPUError = nil
                    onReady(result)
                }
            } catch {
                DispatchQueue.main.async {
                    self.rendering = false
                    self.lastGPUError = error.localizedDescription
                }
            }
        }
    }

    private func makeDisplayImage(buffer: CVPixelBuffer, version: UInt64, uniforms: [SIMD4<Float>]) throws -> CGImage {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        var wrapper: CVMetalTexture?
        guard let cache,
              CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
                                                        width, height, 0, &wrapper) == kCVReturnSuccess,
              let wrapper, let source = CVMetalTextureGetTexture(wrapper),
              let command = queue.makeCommandBuffer() else {
            throw NSError(domain: "MacDuo", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取桌面 GPU 纹理"])
        }
        if outputTexture?.width != width || outputTexture?.height != height {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            d.storageMode = .private; d.usage = [.renderTarget, .shaderRead]
            outputTexture = device.makeTexture(descriptor: d)
        }
        guard let outputTexture else { throw NSError(domain: "MacDuo", code: 3) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = outputTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        encode(command: command, descriptor: pass, texture: source, width: width, height: height,
               refreshSource: version != cachedVersion, settings: uniforms)
        displayStorage.removeAll { $0.width != width || $0.height != height }
        let storage: DisplayStorage
        if let available = displayStorage.first(where: { $0.acquire() }) {
            storage = available
        } else {
            guard let allocated = DisplayStorage(device: device, width: width, height: height) else {
                throw NSError(domain: "MacDuo", code: 5)
            }
            _ = allocated.acquire(); displayStorage.append(allocated); storage = allocated
        }
        guard let blit = command.makeBlitCommandEncoder() else {
            storage.release(); throw NSError(domain: "MacDuo", code: 5)
        }
        blit.copy(from: outputTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: storage.buffer,
                  destinationOffset: 0, destinationBytesPerRow: storage.bytesPerRow,
                  destinationBytesPerImage: storage.buffer.length)
        blit.endEncoding()
        command.commit()
        withExtendedLifetime((buffer, wrapper)) { command.waitUntilCompleted() }
        if let error = command.error { storage.release(); throw error }
        guard command.status == .completed else { storage.release(); throw NSError(domain: "MacDuo", code: 4) }
        let gpuMilliseconds = (command.gpuEndTime - command.gpuStartTime) * 1000
        DispatchQueue.main.async { self.lastGPUMilliseconds = gpuMilliseconds }
        cachedVersion = version
        let retained = Unmanaged.passRetained(storage)
        guard let provider = CGDataProvider(dataInfo: retained.toOpaque(), data: storage.buffer.contents(),
                                            size: storage.buffer.length, releaseData: { info, _, _ in
            guard let info else { return }
            let owner = Unmanaged<DisplayStorage>.fromOpaque(info).takeRetainedValue()
            owner.release()
        }) else {
            retained.release(); storage.release(); throw NSError(domain: "MacDuo", code: 5)
        }
        guard let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: storage.bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw NSError(domain: "MacDuo", code: 6)
        }
        return image
    }

    private func encode(command: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor,
                        texture: MTLTexture, width: Int, height: Int, refreshSource: Bool = true, settings: [SIMD4<Float>]? = nil) {
        let resized = gaussianTextures.first?.width != width || gaussianTextures.first?.height != height
            || gaussianTextures.first?.pixelFormat != texture.pixelFormat
        if resized {
            gaussianTextures.removeAll(); gaussianKernels.removeAll(); scaledTextures.removeAll()
            let sigmas: [Float] = [2, 5, 12, 28, 64]
            var previous: Float = 0
            let scales = [1, 1, 2, 4, 8]
            for (index, sigma) in sigmas.enumerated() {
                let levelWidth = (width + scales[index] - 1) / scales[index]
                let levelHeight = (height + scales[index] - 1) / scales[index]
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat,
                                                                width: levelWidth, height: levelHeight, mipmapped: false)
                d.storageMode = .private; d.usage = [.shaderRead, .shaderWrite]
                guard let t = device.makeTexture(descriptor: d), let scaled = device.makeTexture(descriptor: d) else { return }
                gaussianTextures.append(t); scaledTextures.append(scaled)
                // Convolving Gaussian kernels adds variances, not radii.
                let kernel = MPSImageGaussianBlur(device: device,
                    sigma: sqrt(sigma * sigma - previous * previous) * Float(levelHeight) / 1000)
                kernel.edgeMode = .zero
                gaussianKernels.append(kernel)
                previous = sigma
            }
        }
        if refreshSource || resized {
            var input = texture
            for (index, output) in gaussianTextures.enumerated() {
                if input.width != output.width || input.height != output.height {
                    scaler.encode(commandBuffer: command, sourceTexture: input, destinationTexture: scaledTextures[index])
                    input = scaledTextures[index]
                }
                let kernel = gaussianKernels[index]
                kernel.encode(commandBuffer: command, sourceTexture: input, destinationTexture: output)
                input = output
            }
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        var uniforms = settings ?? [SIMD4<Float>(openness, fullAngle, Float(width), Float(height)),
                        SIMD4<Float>(strength, sin(fullAngle * .pi / 180), 2.4, 0)]
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTextures([texture] + gaussianTextures, range: 0..<6)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride * 2, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // Deterministic GPU render for QA, using synthetic content only.
    func renderTestFrame(image: CGImage, openness: Float, to url: URL) throws {
        self.openness = openness
        // Normalize AppKit's display-profile image to an 8-bit source texture.
        // MTKTextureLoader rejects some extended-range images from lockFocus.
        var sourceBytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let sourceContext = CGContext(data: &sourceBytes, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        sourceContext.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let sd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                         width: image.width, height: image.height, mipmapped: false)
        sd.storageMode = .shared
        let source = device.makeTexture(descriptor: sd)!
        source.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                       withBytes: sourceBytes, bytesPerRow: image.width * 4)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                        width: image.width, height: image.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        let output = device.makeTexture(descriptor: d)!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let command = queue.makeCommandBuffer()!
        encode(command: command, descriptor: pass, texture: source, width: image.width, height: image.height)
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        output.getBytes(&bytes, bytesPerRow: image.width * 4,
                        from: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0)
        let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}

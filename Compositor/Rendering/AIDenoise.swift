import AppKit
import CoreML

nonisolated enum AIDenoiseError: LocalizedError {
    case missingModel, invalidModel, unsupportedHDR, render
    var errorDescription: String? {
        switch self {
        case .missingModel: "The AI denoise model is missing. Reinstall the application."
        case .invalidModel: "The AI denoise model could not be loaded. Reinstall the application."
        case .unsupportedHDR: "AI Denoise supports SDR photo layers. Convert the HDR image to SDR first."
        case .render: "AI Denoise could not process this image."
        }
    }
}

/// Cancellation crosses the detached preview worker; cancelling its parent task alone does not stop inference.
nonisolated final class AIDenoiseControl: @unchecked Sendable {
    let id: UUID
    private let lock = NSLock()
    private var cancelled = false
    private let progress: @Sendable (Double) -> Void
    init(id: UUID = UUID(), progress: @escaping @Sendable (Double) -> Void = { _ in }) {
        self.id = id
        self.progress = progress
    }
    func cancel() { lock.withLock { cancelled = true } }
    func checkCancellation() throws {
        if lock.withLock({ cancelled }) || Task.isCancelled { throw CancellationError() }
    }
    func report(_ fraction: Double) { progress(fraction) }
}

/// KAIR's color FFDNet, running locally. Overlapping tiles keep the convolution's padding out of the result,
/// and even tile origins preserve PixelUnShuffle's phase. Alpha is never sent through the network.
nonisolated enum AIDenoise {
    static let tileSide = 256
    static let halo = 32
    static let step = tileSide - halo * 2
    private static let modelLock = NSLock()
    nonisolated(unsafe) private static var cachedModel: MLModel?

    static func run(_ image: CGImage, amount: Double, control: AIDenoiseControl? = nil) throws -> CGImage {
        let amount = amount.isFinite ? min(100, max(0, amount)) : 50
        guard amount > 0 else { return image }
        try control?.checkCancellation()
        guard !image.bitmapInfo.contains(.floatComponents) else { throw AIDenoiseError.unsupportedHDR }
        let model = try loadModel()
        try control?.checkCancellation()
        let bits = image.bitsPerComponent > 8 ? 16 : 8
        let output = try bitmap(width: image.width, height: image.height, bits: bits)
        guard let outputData = output.data else { throw AIDenoiseError.render }
        let input = try MLMultiArray(shape: [1, 3, NSNumber(value: tileSide), NSNumber(value: tileSide)], dataType: .float32)
        let sigma = try MLMultiArray(shape: [1, 1, 1, 1], dataType: .float32)
        sigma[0] = NSNumber(value: amount * 0.5 / 255)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["noisy": input, "sigma": sigma])
        let plane = tileSide * tileSide
        let tensor = input.dataPointer.assumingMemoryBound(to: Float.self)
        let columns = (image.width + step - 1) / step, rows = (image.height + step - 1) / step
        control?.report(0)
        for row in 0..<rows {
            for column in 0..<columns {
                try control?.checkCancellation()
                try autoreleasepool {
                    let x = column * step, y = row * step
                    let tile = try readTile(image, x: x - halo, y: y - halo)
                    guard let data = tile.data else { throw AIDenoiseError.render }
                    let pixels = data.assumingMemoryBound(to: UInt16.self)
                    let pitch = tile.bytesPerRow / 2
                    // FFDNet expects straight sRGB, not premultiplied RGB or linear light.
                    for ty in 0..<tileSide {
                        for tx in 0..<tileSide {
                            let p = ty * pitch + tx * 4, index = ty * tileSide + tx
                            let alpha = Float(pixels[p + 3])
                            for c in 0..<3 { tensor[c * plane + index] = alpha > 0 ? Float(pixels[p + c]) / alpha : 0 }
                        }
                    }
                    let prediction = try model.prediction(from: provider)
                    try control?.checkCancellation()
                    guard let clean = prediction.featureValue(for: "clean")?.multiArrayValue,
                          clean.shape.map(\.intValue) == [1, 3, tileSide, tileSide], clean.dataType == .float32 else {
                        throw AIDenoiseError.invalidModel
                    }
                    let values = clean.dataPointer.assumingMemoryBound(to: Float.self)
                    let strides = clean.strides.map(\.intValue)
                    for dy in 0..<min(step, image.height - y) {
                        for dx in 0..<min(step, image.width - x) {
                            let source = (dy + halo) * pitch + (dx + halo) * 4
                            let alpha = pixels[source + 3]
                            let target = (y + dy) * output.bytesPerRow + (x + dx) * (bits == 16 ? 8 : 4)
                            for c in 0..<4 {
                                let value: UInt16
                                if c == 3 { value = alpha }
                                else {
                                    let v = values[c * strides[1] + (dy + halo) * strides[2] + (dx + halo) * strides[3]]
                                    guard v.isFinite else { throw AIDenoiseError.render }
                                    value = UInt16((min(1, max(0, v)) * Float(alpha)).rounded())
                                }
                                if bits == 16 { outputData.storeBytes(of: value, toByteOffset: target + c * 2, as: UInt16.self) }
                                else { outputData.storeBytes(of: UInt8((UInt32(value) + 128) / 257), toByteOffset: target + c, as: UInt8.self) }
                            }
                        }
                    }
                    withExtendedLifetime(tile) {}
                }
                control?.report(Double(row * columns + column + 1) / Double(rows * columns))
            }
        }
        try control?.checkCancellation()
        guard let result = output.makeImage() else { throw AIDenoiseError.render }
        return result
    }

    private static func loadModel() throws -> MLModel {
        try modelLock.withLock {
            if let cachedModel { return cachedModel }
            let bundle = Bundle.main
            guard let url = bundle.url(forResource: "FFDNetColor", withExtension: "mlmodelc")
                    ?? bundle.url(forResource: "FFDNetColor", withExtension: "mlmodel") else { throw AIDenoiseError.missingModel }
            do {
                let compiled = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
                defer { if url.pathExtension != "mlmodelc" { try? FileManager.default.removeItem(at: compiled) } }
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                let model = try MLModel(contentsOf: compiled, configuration: configuration)
                cachedModel = model
                return model
            } catch { throw AIDenoiseError.invalidModel }
        }
    }

    private static func bitmap(width: Int, height: Int, bits: Int) throws -> CGContext {
        let order = bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bits,
                                      bytesPerRow: width * 4 * (bits / 8), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | order) else {
            throw AIDenoiseError.render
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        return context
    }

    /// Only one tile is expanded to 16 bits at a time, even for a large photo. Replicate the image's outside edge.
    private static func readTile(_ image: CGImage, x: Int, y: Int) throws -> CGContext {
        let tile = try bitmap(width: tileSide, height: tileSide, bits: 16)
        let rect = CGRect(x: x, y: y, width: tileSide, height: tileSide)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let cropped = image.cropping(to: rect), let data = tile.data else { throw AIDenoiseError.render }
        tile.saveGState()
        tile.translateBy(x: rect.minX - CGFloat(x), y: rect.minY - CGFloat(y) + CGFloat(cropped.height))
        tile.scaleBy(x: 1, y: -1)
        tile.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        tile.restoreGState()
        let pixels = data.assumingMemoryBound(to: UInt16.self), pitch = tile.bytesPerRow / 2
        let left = Int(rect.minX) - x, top = Int(rect.minY) - y
        let right = left + cropped.width - 1, bottom = top + cropped.height - 1
        for ty in 0..<tileSide {
            for tx in 0..<tileSide where tx < left || tx > right || ty < top || ty > bottom {
                let source = min(bottom, max(top, ty)) * pitch + min(right, max(left, tx)) * 4
                let target = ty * pitch + tx * 4
                for c in 0..<4 { pixels[target + c] = pixels[source + c] }
            }
        }
        return tile
    }
}

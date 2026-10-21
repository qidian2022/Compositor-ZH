import AppKit
import Foundation

@main struct AIDenoiseRegression {
    struct Failure: Error, CustomStringConvertible { let description: String }
    nonisolated final class CancellationProbe: @unchecked Sendable {
        weak var control: AIDenoiseControl?
    }
    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }
    static func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try BrushRaster.copy(image)
        guard let data = context.data else { throw Failure(description: "Missing pixels") }
        return withExtendedLifetime(context) {
            (0..<image.height).flatMap { y in
                Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self) + y * context.bytesPerRow,
                                          count: image.width * 4))
            }
        }
    }
    static func fixture(width: Int, height: Int) throws -> (CGImage, [UInt8]) {
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        guard let data = context.data else { throw Failure(description: "Missing fixture pixels") }
        let p = data.assumingMemoryBound(to: UInt8.self)
        var clean = [UInt8](repeating: 0, count: width * height * 4)
        var seed: UInt64 = 12345
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 32) / Double(UInt32.max)
        }
        for y in 0..<height {
            for x in 0..<width {
                let color = x < width / 2 ? [64, 115, 165] : [192, 140, 90]
                for c in 0..<3 {
                    let noise = (0..<12).reduce(0.0) { sum, _ in sum + random() } - 6
                    let value = color[c] + y * 24 / height
                    p[y * context.bytesPerRow + x * 4 + c] = UInt8(min(255, max(0, (Double(value) + noise * 25).rounded())))
                    clean[(y * width + x) * 4 + c] = UInt8(value)
                }
                p[y * context.bytesPerRow + x * 4 + 3] = 255
                clean[(y * width + x) * 4 + 3] = 255
            }
        }
        return (context.makeImage()!, clean)
    }
    @MainActor static func wait(_ session: EditorSession) async {
        while let task = session.filterEdit?.previewTask { await task.value }
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let (source, clean) = try fixture(width: 397, height: 205)
        let original = try pixels(source)
        let zero = try AIDenoise.run(source, amount: 0)
        try check(zero === source, "Zero amount must preserve the original")
        let started = Date()
        let denoised = try AIDenoise.run(source, amount: 50)
        let made = try pixels(denoised)
        var before = 0.0, after = 0.0
        for i in original.indices where i % 4 != 3 {
            before += pow(Double(original[i]) - Double(clean[i]), 2)
            after += pow(Double(made[i]) - Double(clean[i]), 2)
        }
        try check(after < before * 0.5, "Denoising did not reduce synthetic noise sufficiently: \(after / before)")
        let left = (100 * 397 + 150) * 4, right = (100 * 397 + 240) * 4
        try check(Int(made[right]) - Int(made[left]) > 90, "Lost the photo's edge or swapped color channels")
        print("PASS neural denoising: MSE ratio \(after / before), \(Date().timeIntervalSince(started)) seconds")

        // Moving the tile grid by an even offset must not change pixels at the old seams.
        let shifted = try BrushRaster.context(width: 413, height: 221, mask: false)
        BrushRaster.draw(source, in: CGRect(x: 16, y: 16, width: 397, height: 205), mask: false, context: shifted)
        let shiftedResult = try pixels(AIDenoise.run(shifted.makeImage()!, amount: 50))
        var worst = 0
        for y in 48..<157 {
            for x in 180..<205 {
                for c in 0..<3 {
                    worst = max(worst, abs(Int(made[(y * 397 + x) * 4 + c]) - Int(shiftedResult[((y + 16) * 413 + x + 16) * 4 + c])))
                }
            }
        }
        try check(worst <= 2, "Tile seam or PixelUnShuffle phase error: \(worst)")
        print("PASS overlapping tiles and phase alignment, max seam difference \(worst)/255")

        let alphaContext = try BrushRaster.context(width: 13, height: 7, mask: false)
        alphaContext.setFillColor(CGColor(srgbRed: 0.5, green: 0.3, blue: 0.7, alpha: 0.5))
        alphaContext.fill(CGRect(x: 0, y: 0, width: 7, height: 7))
        let alphaImage = alphaContext.makeImage()!
        let alphaSource = try pixels(alphaImage), alphaResult = try pixels(AIDenoise.run(alphaImage, amount: 50))
        try check(stride(from: 3, to: alphaSource.count, by: 4).allSatisfy { alphaSource[$0] == alphaResult[$0] }, "Alpha changed")
        for (width, height) in [(1, 1), (1, 9), (9, 1)] {
            let tiny = try fixture(width: width, height: height).0
            let result = try AIDenoise.run(tiny, amount: 50)
            try check(result.width == width && result.height == height, "Tiny photo dimensions changed")
        }
        let deep = try DeepLayer.image(alphaImage)
        let deepResult = try AIDenoise.run(deep, amount: 50)
        try check(deepResult.bitsPerComponent == 16, "16-bit image was reduced to 8 bits")
        let control = AIDenoiseControl(); control.cancel()
        do { _ = try AIDenoise.run(source, amount: 50, control: control); throw Failure(description: "Cancellation was ignored") }
        catch is CancellationError {}
        let probe = CancellationProbe()
        let midway = AIDenoiseControl { fraction in if fraction > 0 { probe.control?.cancel() } }
        probe.control = midway
        do { _ = try AIDenoise.run(source, amount: 50, control: midway); throw Failure(description: "Mid-render cancellation was ignored") }
        catch is CancellationError {}
        do { _ = try AIDenoise.run(DeepLayer.hdr(alphaImage).makeImage()!, amount: 50); throw Failure(description: "HDR silently clipped") }
        catch AIDenoiseError.unsupportedHDR {}
        print("PASS alpha, odd and tiny sizes, 16-bit output, cancellation, HDR protection")

        let session = EditorSession()
        session.insert(ImportedImage(image: source, thumbnail: source, name: "Noisy photo"))
        session.beginFilter(.aiDenoise)
        var settings = session.filterEdit!.settings
        settings.denoiseAmount = 25
        session.updateFilter(settings, preview: true)
        settings.denoiseAmount = 50
        session.updateFilter(settings, preview: true)
        await wait(session)
        try check(session.filterEdit?.previewError == nil, "Preview failed: \(session.filterEdit?.previewError ?? "unknown")")
        let preview = session.filterEdit!.preparedPreview!
        try check(try pixels(preview) == made, "Newest slider setting did not win")
        session.updateFilter(settings, preview: false)
        try check(session.filterEdit!.previewImage(for: session.activeLayerID!) == nil, "Original comparison failed")
        await session.commitFilter()
        try check(session.filterEdit == nil && session.lastFilter == .aiDenoise, "Filter did not commit")
        try check(try pixels(session.activeLayer!.asset!.image) == made, "Committed image differs from preview")
        session.undo()
        try check(session.activeLayer!.asset!.image === source, "Undo did not restore original")
        session.redo()
        try check(try pixels(session.activeLayer!.asset!.image) == made, "Redo did not restore denoising")
        session.beginFilter(.aiDenoise)
        session.cancelFilter()
        try check(session.filterEdit == nil, "Cancel left filter open")
        print("PASS latest preview, original comparison, cached commit, undo, redo, cancel")

        let deepSession = EditorSession()
        deepSession.insert(try DeepLayer.asset(deep, name: "16-bit photo"))
        deepSession.beginFilter(.aiDenoise)
        await wait(deepSession)
        let deepPreview = deepSession.filterEdit!.preparedPreview!
        try check(deepPreview.bitsPerComponent == 16, "16-bit preview lost precision")
        await deepSession.commitFilter()
        let committedDeep = deepSession.activeLayer!.asset!.deep!
        try check(committedDeep.bitsPerComponent == 16, "16-bit commit lost precision")
        let previewData = deepPreview.dataProvider!.data! as Data
        let committedData = committedDeep.dataProvider!.data! as Data
        try check(previewData == committedData, "16-bit commit differs from its preview")
        print("PASS 16-bit preview and cached commit")

        let selected = EditorSession()
        selected.insert(ImportedImage(image: source, thumbnail: source, name: "Selection"))
        selected.document?.selection = DocumentSelection(path: CGPath(rect: CGRect(x: 0, y: 0, width: 150, height: 205), transform: nil))
        selected.beginFilter(.aiDenoise)
        await wait(selected)
        await selected.commitFilter()
        let limited = try pixels(selected.activeLayer!.asset!.image)
        for y in 0..<205 {
            for x in 160..<397 {
                let offset = (y * 397 + x) * 4
                for c in 0..<4 {
                    try check(limited[offset + c] == original[offset + c], "Pixels outside the selection changed")
                }
            }
        }
        print("PASS selected-area denoising")
    }
}

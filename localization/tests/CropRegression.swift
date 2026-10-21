import AppKit
import Foundation

@main struct CropRegression {
    struct Failure: Error, CustomStringConvertible { let description: String }
    @MainActor static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }
    @MainActor static func fixture() throws -> EditorSession {
        let ctx = try BrushRaster.context(width: 12, height: 8, mask: false)
        for y in 0..<8 {
            for x in 0..<12 {
                ctx.setFillColor(CGColor(srgbRed: CGFloat(x + y * 12) / 100, green: 0.2, blue: 0.3, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let image = ctx.makeImage()!
        let session = EditorSession()
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Test pixels"))
        return session
    }
    @MainActor static func pixels(_ session: EditorSession) async throws -> [UInt8] {
        let raster = try await ImageExporter.shared.render(session.projectSnapshot()!)
        let context = try BrushRaster.copy(raster.image)
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<raster.image.height).flatMap { y in
            Array(UnsafeBufferPointer(start: data + y * context.bytesPerRow, count: raster.image.width * 4))
        }
    }
    @MainActor static func crop(_ session: EditorSession, _ rect: CGRect) async throws {
        session.selectTool(.crop)
        session.cropRect = rect
        await session.commitCrop()
        try check(session.cropError == nil && session.document?.cropMask != nil, "crop did not commit")
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let free = CropDrag(start: CGPoint(x: 100, y: 60), original: CGRect(x: 0, y: 0, width: 100, height: 60), mode: .resize(4))
        let freeResult = free.updated(to: CGPoint(x: 140, y: 70), ratio: nil)
        try check(freeResult == CGRect(x: 0, y: 0, width: 140, height: 70), "free crop unexpectedly constrained")
        // The requested ratio, not the frame's old ratio, must win for every handle.
        for index in 0..<8 {
            let rect = CGRect(x: 30, y: 20, width: 120, height: 80)
            let handle = LayerTransform.handles[index]
            let start = CGPoint(x: rect.minX + handle.x * rect.width, y: rect.minY + handle.y * rect.height)
            let drag = CropDrag(start: start, original: rect, mode: .resize(index))
            for symmetric in [false, true] {
                let next = drag.updated(to: CGPoint(x: start.x + 17, y: start.y + 13), ratio: 1, symmetric: symmetric)
                try check(next.width == next.height, "fixed ratio drifted at handle \(index)")
                if symmetric { try check(next.midX == rect.midX && next.midY == rect.midY, "symmetric crop moved its center") }
            }
        }
        print("PASS free and explicit-ratio geometry, all eight handles")

        let s = try fixture()
        let originalPixels = try await pixels(s)
        let originalImage = s.document!.layers[0].asset!.image
        s.document?.layers[0].mask = LayerMask.solid(revealing: true)
        s.document?.layers[0].mask?.placement = LayerTransform(origin: CGPoint(x: 1, y: 1), size: CGSize(width: 12, height: 8))
        s.document?.layers[0].mask?.isLinked = false
        let originalMask = s.document!.layers[0].mask
        let maskedPixels = try await pixels(s)
        try await crop(s, CGRect(x: 2, y: 1, width: 6, height: 4))
        try check(s.document!.size == CGSize(width: 6, height: 4), "cropped canvas dimensions")
        try check(s.document!.layers[0].asset!.image === originalImage, "crop resampled or replaced source pixels")
        try check(s.document!.layers[0].mask!.asset.image === originalMask!.asset.image, "crop overwrote an existing layer mask")
        s.cropRatioChoice = "Original"
        try check(s.cropRatio == 1.5, "Original no longer uses the imported photo")
        s.cropRatioChoice = "1:1"; s.changeCropRatio()
        s.cropRatioChoice = "Free"; s.changeCropRatio()
        try check(s.cropRatio == nil, "Free retains the previous ratio")
        s.cancelCrop()
        await s.toggleCropMask()
        try check(s.document!.size == CGSize(width: 12, height: 8), "hiding crop did not restore bounds")
        try check(s.document!.layers[0].mask == originalMask, "unlinked layer mask moved after restore")
        try check(try await pixels(s) == maskedPixels, "hiding crop did not restore all pixels")
        s.document?.layers[0].opacity = 0.5
        await s.toggleCropMask()
        try check(s.document!.layers[0].opacity == 0.5, "show crop discarded subsequent edits")
        s.undo()
        try check(s.document!.cropMask?.isEnabled == false, "undo visibility")
        s.redo()
        try check(s.document!.cropMask?.isEnabled == true, "redo visibility")
        let png = try await ImageExporter.shared.pngData(s.projectSnapshot()!)
        let bitmap = NSBitmapImageRep(data: png)!
        try check(bitmap.pixelsWide == 6 && bitmap.pixelsHigh == 4, "export ignored crop size")
        print("PASS source/mask preservation, original ratio, toggle, edit preservation, undo/redo and export")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("crop.comp")
        for enabled in [true, false] {
            if s.document!.cropMask!.isEnabled != enabled { await s.toggleCropMask() }
            let snapshot = s.projectSnapshot()!
            try await ProjectStore.shared.save(snapshot, to: url)
            let loaded = try await ProjectStore.shared.load(from: url)
            let reopened = EditorSession()
            reopened.installProject(loaded, from: url)
            try check(reopened.document!.cropMask == s.document!.cropMask, "crop visibility/geometry did not persist")
            try check(reopened.document!.originalAspectRatio == 1.5, "import ratio did not persist")
            await reopened.removeCropMask()
            try check(reopened.document!.size == CGSize(width: 12, height: 8) && reopened.document!.cropMask == nil, "remove saved crop")
        }
        print("PASS enabled and hidden project save/load; removal restores full canvas")

        let repeatCrop = try fixture()
        try await crop(repeatCrop, CGRect(x: 2, y: 1, width: 8, height: 6))
        try await crop(repeatCrop, CGRect(x: 1, y: 1, width: 4, height: 3))
        try check(repeatCrop.document!.cropMask!.rect.origin == CGPoint(x: 3, y: 2), "consecutive crops lost their original origin")
        await repeatCrop.removeCropMask()
        try check(try await pixels(repeatCrop) == originalPixels, "consecutive crop removal lost content")
        repeatCrop.undo()
        try check(repeatCrop.document!.size == CGSize(width: 4, height: 3), "undo crop removal")
        print("PASS consecutive crops and undo removal")

        for clockwise in [true, false] {
            let cropped = try fixture(), control = try fixture()
            try await crop(cropped, CGRect(x: 2, y: 1, width: 6, height: 4))
            cropped.rotateCanvas(clockwise: clockwise)
            control.rotateCanvas(clockwise: clockwise)
            await cropped.removeCropMask()
            try check(try await pixels(cropped) == pixels(control), "rotate then uncrop differs from rotating full original")
        }
        for horizontally in [true, false] {
            let cropped = try fixture(), control = try fixture()
            try await crop(cropped, CGRect(x: 2, y: 1, width: 6, height: 4))
            cropped.flipCanvas(horizontally: horizontally)
            control.flipCanvas(horizontally: horizontally)
            await cropped.removeCropMask()
            try check(try await pixels(cropped) == pixels(control), "flip then uncrop differs from flipping full original")
        }
        print("PASS rotation and flips preserve restoration coordinates")

        let resized = try fixture()
        try await crop(resized, CGRect(x: 2, y: 1, width: 6, height: 4))
        let scaled = try await ImageResizer.shared.resize(resized.projectSnapshot()!, to: ImageSizeOptions(width: 12, height: 8, resolution: 72))
        resized.applyImageSize(scaled)
        await resized.removeCropMask()
        try check(resized.document!.size == CGSize(width: 24, height: 16), "image resize lost full canvas dimensions")
        try check(resized.document!.layers[0].origin == .zero, "image resize lost full image placement")
        let canvas = try fixture()
        try await crop(canvas, CGRect(x: 2, y: 1, width: 6, height: 4))
        let expanded = try await CanvasResizer.shared.resize(canvas.projectSnapshot()!, to: CanvasSizeOptions(width: 8, height: 6))
        canvas.applyDocumentSize(expanded, actionName: "Canvas Size")
        await canvas.removeCropMask()
        try check(try await pixels(canvas) == originalPixels, "canvas resize lost restoration coordinates")
        print("PASS image and canvas resizing")

        let validation = try fixture()
        try await crop(validation, CGRect(x: 2, y: 1, width: 6, height: 4))
        let good = validation.projectSnapshot()!
        var invalid = good.manifest
        invalid.cropMask?.rect.size.width = 5
        do { try await ProjectStore.shared.save(ProjectSnapshot(manifest: invalid, images: good.images), to: url); throw Failure(description: "invalid crop accepted") }
        catch ProjectError.invalid { }
        invalid = good.manifest; invalid.version = 14
        do { try await ProjectStore.shared.save(ProjectSnapshot(manifest: invalid, images: good.images), to: url); throw Failure(description: "crop metadata accepted in old format") }
        catch ProjectError.invalid { }
        var legacy = good.manifest; legacy.version = 14; legacy.cropMask = nil; legacy.originalAspectRatio = nil
        try await ProjectStore.shared.save(ProjectSnapshot(manifest: legacy, images: good.images), to: url)
        let legacySession = EditorSession()
        legacySession.installProject(try await ProjectStore.shared.load(from: url), from: url)
        legacySession.cropRatioChoice = "Original"
        try check(legacySession.cropRatio == 1.5, "legacy project did not infer full layer image ratio")
        print("PASS malformed metadata rejection and legacy project loading")
        print("All crop regression checks passed.")
    }
}

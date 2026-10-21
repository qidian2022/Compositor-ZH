import AppKit
import Foundation
#if !SUBJECT_EXTRACTION_REGRESSION
import Testing
@testable import Compositor
#endif

@MainActor
struct SubjectExtractionTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func check(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(description: message) }
    }

    nonisolated static func gray(_ values: [UInt8], width: Int = 3, height: Int = 2) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(values) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw ExportError.render }
        return image
    }

    static func bytes(_ image: CGImage, mask: Bool = true) throws -> [UInt8] {
        let context = try PixelAdjust.bitmap(width: image.width, height: image.height, mask: mask)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { throw ExportError.render }
        return (0..<image.height).flatMap { y in
            (0..<image.width).map { x in data[y * context.bytesPerRow + x * (mask ? 1 : 4) + (mask ? 0 : 3)] }
        }
    }

    static func fixture() throws -> EditorSession {
        let context = try PixelAdjust.bitmap(width: 3, height: 2, mask: false)
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.2, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        guard let image = context.makeImage() else { throw ExportError.render }
        let session = EditorSession()
        session.insert(ImportedImage(image: image, thumbnail: image, name: "Photo"))
        return session
    }

    static func maskArithmetic() throws {
        let values: [UInt8] = [255, 128, 0, 40, 200, 10]
        let subject = try gray(values)
        let background = try SubjectExtraction.mask(from: subject, region: .background)
        try check(try bytes(background) == values.map { 255 - $0 }, "background lost soft coverage or flipped vertically")
        let existing = try gray([255, 128, 80, 0, 255, 255])
        let combined = try SubjectExtraction.mask(from: subject, region: .subject, under: existing)
        let reverse = try SubjectExtraction.mask(from: subject, region: .background, under: existing)
        for (image, expected) in [(combined, [255, 64, 0, 0, 200, 10]), (reverse, [0, 64, 80, 0, 55, 245])] {
            try check(try zip(bytes(image), expected).allSatisfy { abs(Int($0) - $1) <= 1 }, "existing mask was flipped, lost, or inverted")
        }
        let foreground = try SubjectExtraction.outline(from: subject, region: .subject, canvas: CGSize(width: 3, height: 2))
        let behind = try SubjectExtraction.outline(from: subject, region: .background, canvas: CGSize(width: 3, height: 2))
        for y in 0..<2 { for x in 0..<3 {
            let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
            let expected = values[y * 3 + x] >= 128
            try check(foreground.contains(point) == expected, "subject selection orientation")
            try check(behind.contains(point) != expected, "background selection is not the canvas complement")
        } }
    }

    static func extractionAndHistory() async throws {
        for region in SubjectRegion.allCases {
            let session = try fixture()
            session.document?.layers[0].transform.origin = CGPoint(x: 2, y: -4)
            session.document?.layers[0].transform.rotation = 25
            session.document?.layers[0].transform.flipX = true
            session.document?.layers[0].opacity = 0.6
            session.document?.layers[0].blendMode = .multiply
            session.selectAll()
            let original = session.document!, source = session.activeLayer!, count = session.history.undoCount
            await session.extractSubjectLayers(region, detect: { _ in try gray([255, 128, 0, 40, 200, 10]) })
            try check(!session.isProjectBusy && session.brushError == nil, "extraction left the document busy or failed")
            try check(session.document!.layers.count == 2 && session.history.undoCount == count + 1, "extraction is not one history entry")
            let output = session.activeLayer!
            try check(output.id != source.id && output.asset?.image === source.asset?.image, "source pixels were copied or changed")
            try check(output.transform == source.transform && output.opacity == source.opacity && output.blendMode == source.blendMode,
                      "output lost layer appearance or placement")
            try check(output.mask?.isEnabled == true && output.mask?.isLinked == true, "output mask is not editable and linked")
            try check(!session.document!.layers[0].isVisible && session.document!.layers[0].mask == source.mask, "source was erased or left covering the cutout")
            try check(session.selection == nil && !session.isMaskSelected && session.selectedLayerIDs == [output.id], "output selection state")
            let expected: [UInt8] = region == .subject ? [255, 128, 0, 40, 200, 10] : [0, 127, 255, 215, 55, 245]
            try check(try bytes(output.mask!.asset.image) == expected, "wrong output mask")
            session.undo()
            try check(session.document == original && session.activeLayerID == source.id, "undo did not restore the original document")
            session.redo()
            try check(session.activeLayerID == output.id && session.document!.layers.count == 2, "redo did not restore output")
        }
    }

    static func splitAndPersistence() async throws {
        let session = try fixture()
        session.groupSelectedLayers()
        let folder = session.activeLayerID!
        let sourceID = session.document!.layers.first { !$0.isGroup }!.id
        session.selectLayer(sourceID)
        let count = session.history.undoCount
        await session.extractSubjectLayers(nil, detect: { _ in try gray([255, 128, 0, 40, 200, 10]) })
        let layers = session.document!.layers.filter { !$0.isGroup }
        try check(layers.count == 3 && layers.dropFirst().allSatisfy { $0.parentID == folder }, "split left the source folder")
        try check(layers.dropFirst().allSatisfy(\.isVisible) && !layers[0].isVisible, "split visibility")
        try check(session.selectedLayerIDs == Set(layers.dropFirst().map(\.id)) && session.activeLayerID == layers.last?.id,
                  "split output selection")
        try check(session.history.undoCount == count + 1, "split made multiple history entries")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("subject.comp")
        try await ProjectStore.shared.save(session.projectSnapshot()!, to: url)
        let loaded = try await ProjectStore.shared.load(from: url)
        let reopened = EditorSession()
        reopened.installProject(loaded, from: url)
        try check(reopened.document!.layers.map(\.id) == session.document!.layers.map(\.id), "output layers did not persist")
        for output in layers.dropFirst() {
            let saved = reopened.document!.layers.first { $0.id == output.id }!
            try check(saved.parentID == folder && saved.transform == output.transform, "saved output placement")
            try check(try bytes(saved.mask!.asset.image) == bytes(output.mask!.asset.image), "saved mask coverage")
        }
        try check(!reopened.document!.layers.first { $0.id == sourceID }!.isVisible, "saved original visibility")
    }

    static func placedAndDisabledMasks() async throws {
        for disabled in [false, true] {
            let session = try fixture()
            let originalMask = LayerMask(asset: try LayerMask.asset(from: gray([0, 255, 0, 255, 0, 255])),
                                         isEnabled: !disabled,
                                         placement: LayerTransform(origin: CGPoint(x: 1, y: 0), size: CGSize(width: 3, height: 2)),
                                         isLinked: false)
            session.document?.layers[0].mask = originalMask
            let existing = originalMask.clipImage(placement: originalMask.placement, over: session.activeLayer!.transform, width: 3, height: 2)
            await session.extractSubjectLayers(.background, detect: { _ in try gray([255, 128, 0, 40, 200, 10]) })
            let output = session.activeLayer!
            let expected = try SubjectExtraction.mask(from: gray([255, 128, 0, 40, 200, 10]), region: .background, under: existing)
            try check(try bytes(output.mask!.asset.image) == bytes(expected), "placed/disabled mask coverage")
            try check(session.document!.layers[0].mask == originalMask && output.mask?.placement == nil, "source mask metadata changed")
            // Render without transforms to catch accidental inversion of the new grayscale mask.
            let rendered = try await ImageExporter.shared.render(session.projectSnapshot()!)
            let actual = try bytes(rendered.image, mask: false), coverage = try bytes(expected)
            try check(zip(actual, coverage).allSatisfy { abs(Int($0) - Int($1)) <= 1 }, "export alpha differs from output mask")
        }
    }

    static func failureAndGuards() async throws {
        let session = try fixture()
        let original = session.document, count = session.history.undoCount
        await session.extractSubjectLayers(.subject, detect: { _ in throw SubjectRemoval.Failure.noSubject })
        try check(session.document == original && session.history.undoCount == count && !session.isProjectBusy && session.brushError != nil,
                  "failed detection mutated the source or left busy state")
        session.brushError = nil
        await session.extractSubjectLayers(.background, detect: { _ in try gray([255], width: 1, height: 1) })
        try check(session.document == original && session.history.undoCount == count && !session.isProjectBusy, "invalid model output mutated source")
        session.brushError = nil
        session.addBlankLayer()
        try check(!session.canExtractSubjectLayers, "empty layer can be extracted")
        session.selectLayers(Set(session.document!.layers.map(\.id)), primary: session.document!.layers[0].id)
        try check(!session.canExtractSubjectLayers, "multiple layers can be extracted")
        session.selectLayer(session.document!.layers[0].id)
        try check(session.canExtractSubjectLayers, "image layer is disabled")
        session.isProjectBusy = true
        try check(!session.canExtractSubjectLayers && !session.canSelectSubject, "busy document accepts detection")
        session.isProjectBusy = false
        session.addGroup()
        try check(!session.canExtractSubjectLayers, "folder can be extracted")
    }

    static func staleResult() async throws {
        let session = try fixture()
        let task = Task {
            await session.extractSubjectLayers(.subject, detect: { _ in
                Thread.sleep(forTimeInterval: 0.15)
                return try gray([255, 128, 0, 40, 200, 10])
            })
        }
        while !session.isProjectBusy { await Task.yield() }
        let replacement = CanvasDocument(width: 7, height: 5)
        session.document = replacement
        await task.value
        try check(session.document == replacement && !session.isProjectBusy && session.brushError == nil, "late result changed another document")
    }

#if !SUBJECT_EXTRACTION_REGRESSION
    @Test func coverageAndSelectionOrientation() throws { try Self.maskArithmetic() }
    @Test func outputAndUndoRedo() async throws { try await Self.extractionAndHistory() }
    @Test func splitRoundTrip() async throws { try await Self.splitAndPersistence() }
    @Test func maskPlacementAndExport() async throws { try await Self.placedAndDisabledMasks() }
    @Test func failuresDoNotMutate() async throws { try await Self.failureAndGuards() }
    @Test func documentSwitchDiscardsResult() async throws { try await Self.staleResult() }
#endif
}

#if SUBJECT_EXTRACTION_REGRESSION
@main struct SubjectExtractionRegression {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        try SubjectExtractionTests.maskArithmetic()
        print("PASS soft masks, existing coverage and subject/background selection orientation")
        try await SubjectExtractionTests.extractionAndHistory()
        print("PASS new layers, source preservation, transforms, appearance and undo/redo")
        try await SubjectExtractionTests.splitAndPersistence()
        print("PASS two-layer split, folder placement and project save/load")
        try await SubjectExtractionTests.placedAndDisabledMasks()
        print("PASS placed/disabled masks and exported alpha")
        try await SubjectExtractionTests.failureAndGuards()
        print("PASS detection failures, invalid output and unavailable actions")
        try await SubjectExtractionTests.staleResult()
        print("PASS stale detection result after switching documents")
    }
}
#endif

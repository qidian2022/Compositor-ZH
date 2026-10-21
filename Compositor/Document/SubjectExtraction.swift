import AppKit

nonisolated enum SubjectRegion: String, CaseIterable, Sendable {
    case subject = "Subject"
    case background = "Background"

    var selectionName: String { self == .subject ? "Select Subject" : "Select Background" }
    var layerName: String { self == .subject ? "Subject to New Layer" : "Background to New Layer" }
}

/// Keeps Vision's soft coverage for layer output; only selections are traced into hard outlines.
nonisolated enum SubjectExtraction {
    static func mask(from subject: CGImage, region: SubjectRegion, under existing: CGImage? = nil) throws -> CGImage {
        guard LayerMask.isValid(subject) else { throw ProjectError.invalid }
        let coverage = try region == .subject ? subject : PixelInvert.run(.init(
            image: subject, isMask: true, pixelToDocument: .identity, selection: nil))
        guard let existing else { return coverage }
        let context = try PixelAdjust.bitmap(width: subject.width, height: subject.height, mask: true)
        let bounds = CGRect(x: 0, y: 0, width: subject.width, height: subject.height)
        context.draw(existing, in: bounds)
        context.setBlendMode(.multiply)
        context.draw(coverage, in: bounds)
        guard let combined = context.makeImage() else { throw ExportError.render }
        return combined
    }

    static func outline(from subject: CGImage, region: SubjectRegion, canvas: CGSize) throws -> CGPath {
        guard let traced = MaskTracing.whitePixels(in: subject) else { throw SubjectRemoval.Failure.noSubject }
        var mapping = BrushRaster.pixelToDocument(LayerTransform(origin: .zero, size: canvas),
                                                  width: subject.width, height: subject.height)
        guard let foreground = traced.copy(using: &mapping) else { throw ExportError.render }
        let bounds = CGPath(rect: CGRect(origin: .zero, size: canvas), transform: nil)
        return region == .subject ? foreground : bounds.subtracting(foreground, using: .winding)
    }
}

private nonisolated struct SubjectExtractionJob: @unchecked Sendable {
    let image: CGImage
    let mask: LayerMask?
    let transform: LayerTransform
    let regions: [SubjectRegion]

    func run(detect: @Sendable (CGImage) throws -> CGImage) throws -> [LayerMask] {
        let subject = try detect(image)
        guard subject.width == image.width, subject.height == image.height else { throw ProjectError.invalid }
        try Task.checkCancellation()
        let existing = mask?.clipImage(placement: mask?.placement, over: transform, width: image.width, height: image.height)
        if mask?.isEnabled == true, existing == nil { throw ExportError.render }
        return try regions.map { region in
            LayerMask(asset: try LayerMask.asset(from: SubjectExtraction.mask(from: subject, region: region, under: existing)))
        }
    }
}

extension EditorSession {
    var canExtractSubjectLayers: Bool {
        guard canEditLayers, selectedLayerIDs.count == 1, let layer = activeLayer else { return false }
        return layer.asset != nil && !layer.isGroup && layer.adjustment == nil && layer.text == nil && layer.shape == nil
            && (document?.layers.count ?? 10_000) < 10_000 && selectionMoveOrigin == nil && lassoDraft == nil
    }

    /// Nil outputs both regions. The source pixels are shared, while each new layer has its own editable mask.
    /// `detect` also lets regressions exercise the complete async transaction without depending on model guesses.
    func extractSubjectLayers(_ region: SubjectRegion?,
                              detect: @escaping @Sendable (CGImage) throws -> CGImage = {
                                  try SubjectRemoval.subjectMask($0, under: nil, settings: FilterSettings())
                              }) async {
        let regions: [SubjectRegion] = region.map { [$0] } ?? [.background, .subject]
        guard canExtractSubjectLayers, let document, let source = activeLayer, let image = source.asset?.image,
              document.layers.count + regions.count <= 10_000 else { return }
        let job = SubjectExtractionJob(image: image, mask: source.mask, transform: source.transform, regions: regions)
        isProjectBusy = true
        let result = await Task.detached(priority: .userInitiated) { () -> Result<[LayerMask], Error> in
            Result { try job.run(detect: detect) }
        }.value
        isProjectBusy = false
        guard !Task.isCancelled, self.document == document, activeLayerID == source.id,
              let index = self.document?.layers.firstIndex(where: { $0.id == source.id }) else { return }
        switch result {
        case .failure(let error):
            brushError = error.localizedDescription
        case .success(let masks):
            let copies = zip(regions, masks).map { region, mask in
                ImageLayer(id: UUID(), asset: source.asset, name: source.name + " · " + zh(region.rawValue),
                           isVisible: true, transform: source.transform, parentID: source.parentID,
                           opacity: source.opacity, blendMode: source.blendMode, mask: mask,
                           maskSourceID: source.maskSourceID, effects: source.effects)
            }
            beginEdit(region?.layerName ?? "Separate Subject and Background")
            self.document?.layers[index].isVisible = false
            self.document?.layers.insert(contentsOf: copies, at: index + 1)
            self.document?.selection = nil
            activeLayerID = copies.last?.id
            selectedLayerIDs = Set(copies.map(\.id))
            viewsMaskAlone = false
            revealActiveLayer()
            endEdit()
        }
    }
}

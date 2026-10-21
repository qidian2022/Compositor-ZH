import Foundation
import CoreGraphics

/// A reversible document-wide crop. Layer pixels and existing layer masks are never trimmed.
/// `rect` is expressed in the uncropped canvas; enabled layers are translated by -rect.origin.
nonisolated struct CanvasCrop: Codable, Equatable, Sendable {
    var fullSize: CGSize
    var rect: CGRect
    var isEnabled = true

    var visibleSize: CGSize { isEnabled ? rect.size : fullSize }
    var visibleOrigin: CGPoint { isEnabled ? rect.origin : .zero }

    func isValid(width: Int, height: Int) -> Bool {
        let values = [fullSize.width, fullSize.height, rect.minX, rect.minY, rect.width, rect.height]
        guard values.allSatisfy({ $0.isFinite && $0.rounded() == $0 }),
              (1...DocumentLimits.maxSideExtent).contains(fullSize.width),
              (1...DocumentLimits.maxSideExtent).contains(fullSize.height),
              CropGeometry.valid(rect) else { return false }
        return visibleSize == CGSize(width: width, height: height)
    }

    func resizingCanvas(to size: CGSize, offset: CGPoint) -> CanvasCrop {
        var result = self
        if isEnabled {
            result.rect = CGRect(x: rect.minX - offset.x, y: rect.minY - offset.y, width: size.width, height: size.height)
        } else {
            result.fullSize = size
            result.rect = rect.offsetBy(dx: offset.x, dy: offset.y)
        }
        return result
    }

    func scaled(x: CGFloat, y: CGFloat, visibleSize: CGSize) -> CanvasCrop {
        var result = self
        result.fullSize = CGSize(width: max(1, (fullSize.width * x).rounded()), height: max(1, (fullSize.height * y).rounded()))
        result.rect = CropGeometry.snapped(CGRect(x: rect.minX * x, y: rect.minY * y,
                                                 width: rect.width * x, height: rect.height * y))
        if isEnabled { result.rect.size = visibleSize } else { result.fullSize = visibleSize }
        return result
    }

    func quarterTurned(clockwise: Bool) -> CanvasCrop {
        var result = self
        result.fullSize = CGSize(width: fullSize.height, height: fullSize.width)
        result.rect = clockwise
            ? CGRect(x: fullSize.height - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
            : CGRect(x: rect.minY, y: fullSize.width - rect.maxX, width: rect.height, height: rect.width)
        return result
    }

    func mirrored(horizontally: Bool) -> CanvasCrop {
        var result = self
        if horizontally { result.rect.origin.x = fullSize.width - rect.maxX }
        else { result.rect.origin.y = fullSize.height - rect.maxY }
        return result
    }
}

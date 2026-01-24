//
//  CropMaskRenderer.swift
//  cropaway
//

import Foundation
import CoreImage
import CoreGraphics

final class CropMaskRenderer: @unchecked Sendable {
    private let ciContext: CIContext

    // Reusable mask context to avoid memory pressure during export
    private var maskContext: CGContext?
    private var maskContextSize: CGSize = .zero
    private let maskQueue = DispatchQueue(label: "com.cropaway.maskRenderer")

    init() {
        // Use Metal for GPU acceleration with memory-efficient settings
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(
                mtlDevice: metalDevice,
                options: [
                    .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
                    .highQualityDownsample: true,
                    .cacheIntermediates: false  // Reduce memory usage
                ]
            )
        } else {
            self.ciContext = CIContext(options: [
                .highQualityDownsample: true,
                .cacheIntermediates: false
            ])
        }
    }

    /// Get or create a reusable CGContext for mask generation
    private func getMaskContext(size: CGSize) -> CGContext? {
        let width = Int(size.width)
        let height = Int(size.height)

        // Reuse existing context if same size
        if let existing = maskContext, maskContextSize == size {
            // Clear the context for reuse
            existing.clear(CGRect(origin: .zero, size: size))
            return existing
        }

        // Create new context if size changed
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        maskContext = context
        maskContextSize = size
        return context
    }

    func generateMask(
        mode: CropMode,
        state: InterpolatedCropState,
        size: CGSize
    ) -> CIImage {
        switch mode {
        case .rectangle:
            return generateRectangleMask(rect: state.cropRect, size: size)
        case .circle:
            return generateCircleMask(
                center: state.circleCenter,
                radius: state.circleRadius,
                size: size
            )
        case .freehand:
            // Try bezier path data first, fall back to simple points
            return generateFreehandMask(pathData: state.freehandPathData, points: state.freehandPoints, size: size)
        case .ai:
            // AI mode uses RLE mask data for pixel-perfect segmentation
            if let maskData = state.aiMaskData {
                return generateAIMask(maskData: maskData, size: size)
            }
            // No mask data yet - return full white (show everything until tracking completes)
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }
    }

    private func generateRectangleMask(rect: CGRect, size: CGSize) -> CIImage {
        let pixelRect = rect.denormalized(to: size)
        // Flip Y for Core Image coordinate system
        let flippedRect = CGRect(
            x: pixelRect.origin.x,
            y: size.height - pixelRect.origin.y - pixelRect.height,
            width: pixelRect.width,
            height: pixelRect.height
        )

        let path = CGMutablePath()
        path.addRect(flippedRect)
        return renderPathToMask(path, size: size)
    }

    private func generateCircleMask(center: CGPoint, radius: Double, size: CGSize) -> CIImage {
        let pixelCenter = center.denormalized(to: size)
        let pixelRadius = radius * min(size.width, size.height)

        // Flip Y for Core Image coordinate system
        let flippedCenter = CGPoint(x: pixelCenter.x, y: size.height - pixelCenter.y)

        let ovalRect = CGRect(
            x: flippedCenter.x - pixelRadius,
            y: flippedCenter.y - pixelRadius,
            width: pixelRadius * 2,
            height: pixelRadius * 2
        )

        let path = CGMutablePath()
        path.addEllipse(in: ovalRect)
        return renderPathToMask(path, size: size)
    }

    private func generateFreehandMask(pathData: Data?, points: [CGPoint], size: CGSize) -> CIImage {
        // Try to use bezier path data if available
        if let data = pathData,
           let vertices = try? JSONDecoder().decode([MaskVertex].self, from: data),
           vertices.count >= 3 {
            return generateFreehandMaskFromVertices(vertices, size: size)
        }

        // Fallback to simple points
        guard points.count >= 3 else {
            // Return full white mask if not enough points
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        let path = CGMutablePath()
        let firstPoint = points[0].denormalized(to: size)
        // Flip Y for Core Image coordinate system
        path.move(to: CGPoint(x: firstPoint.x, y: size.height - firstPoint.y))

        for point in points.dropFirst() {
            let pixelPoint = point.denormalized(to: size)
            path.addLine(to: CGPoint(x: pixelPoint.x, y: size.height - pixelPoint.y))
        }
        path.closeSubpath()

        return renderPathToMask(path, size: size)
    }

    private func generateFreehandMaskFromVertices(_ vertices: [MaskVertex], size: CGSize) -> CIImage {
        let path = CGMutablePath()
        let firstPos = vertices[0].position.denormalized(to: size)
        // Flip Y for Core Image coordinate system
        path.move(to: CGPoint(x: firstPos.x, y: size.height - firstPos.y))

        // Add bezier curve segments
        for i in 1..<vertices.count {
            addBezierSegment(to: path, from: vertices[i - 1], to: vertices[i], size: size)
        }

        // Close the path
        addBezierSegment(to: path, from: vertices[vertices.count - 1], to: vertices[0], size: size)
        path.closeSubpath()

        return renderPathToMask(path, size: size)
    }

    private func addBezierSegment(to path: CGMutablePath, from: MaskVertex, to: MaskVertex, size: CGSize) {
        let fromPx = from.position.denormalized(to: size)
        let toPx = to.position.denormalized(to: size)

        // Flip Y for Core Image coordinate system
        let fromFlipped = CGPoint(x: fromPx.x, y: size.height - fromPx.y)
        let toFlipped = CGPoint(x: toPx.x, y: size.height - toPx.y)

        let hasFromHandle = from.controlOut != nil
        let hasToHandle = to.controlIn != nil

        if hasFromHandle && hasToHandle {
            let ctrl1 = CGPoint(
                x: fromPx.x + from.controlOut!.x * size.width,
                y: size.height - (fromPx.y + from.controlOut!.y * size.height)
            )
            let ctrl2 = CGPoint(
                x: toPx.x + to.controlIn!.x * size.width,
                y: size.height - (toPx.y + to.controlIn!.y * size.height)
            )
            path.addCurve(to: toFlipped, control1: ctrl1, control2: ctrl2)
        } else if hasFromHandle {
            // Quadratic approximation using cubic bezier
            let ctrl = CGPoint(
                x: fromPx.x + from.controlOut!.x * size.width,
                y: size.height - (fromPx.y + from.controlOut!.y * size.height)
            )
            let ctrl1 = CGPoint(
                x: fromFlipped.x + 2.0/3.0 * (ctrl.x - fromFlipped.x),
                y: fromFlipped.y + 2.0/3.0 * (ctrl.y - fromFlipped.y)
            )
            let ctrl2 = CGPoint(
                x: toFlipped.x + 2.0/3.0 * (ctrl.x - toFlipped.x),
                y: toFlipped.y + 2.0/3.0 * (ctrl.y - toFlipped.y)
            )
            path.addCurve(to: toFlipped, control1: ctrl1, control2: ctrl2)
        } else if hasToHandle {
            let ctrl = CGPoint(
                x: toPx.x + to.controlIn!.x * size.width,
                y: size.height - (toPx.y + to.controlIn!.y * size.height)
            )
            let ctrl1 = CGPoint(
                x: fromFlipped.x + 2.0/3.0 * (ctrl.x - fromFlipped.x),
                y: fromFlipped.y + 2.0/3.0 * (ctrl.y - fromFlipped.y)
            )
            let ctrl2 = CGPoint(
                x: toFlipped.x + 2.0/3.0 * (ctrl.x - toFlipped.x),
                y: toFlipped.y + 2.0/3.0 * (ctrl.y - toFlipped.y)
            )
            path.addCurve(to: toFlipped, control1: ctrl1, control2: ctrl2)
        } else {
            path.addLine(to: toFlipped)
        }
    }

    private func generateAIMask(maskData: Data?, size: CGSize) -> CIImage {
        guard let data = maskData else {
            // No mask data - return full white (no masking)
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        // Decode RLE mask data directly to CGImage (handles column-major COCO format)
        guard let (cgImage, maskWidth, maskHeight) = AIMaskResult.decodeMaskToImage(data) else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        // Create CIImage from decoded mask
        var maskImage = CIImage(cgImage: cgImage)

        // Scale to target size if different from mask dimensions
        let scaleX = size.width / CGFloat(maskWidth)
        let scaleY = size.height / CGFloat(maskHeight)
        if abs(scaleX - 1.0) > 0.001 || abs(scaleY - 1.0) > 0.001 {
            maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        }

        return maskImage
    }

    // Thread-safe mask rendering using reusable Core Graphics context
    private func renderPathToMask(_ path: CGPath, size: CGSize) -> CIImage {
        guard let context = getMaskContext(size: size) else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        // Fill black background
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        // Fill white mask area
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(path)
        context.fillPath()

        guard let cgImage = context.makeImage() else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        return CIImage(cgImage: cgImage)
    }

    func applyMask(
        to inputImage: CIImage,
        mask: CIImage,
        preserveWidth: Bool,
        enableAlpha: Bool
    ) -> CIImage {
        let extent = inputImage.extent

        // Create background
        let background: CIImage
        if enableAlpha {
            background = CIImage.clear.cropped(to: extent)
        } else {
            background = CIImage(color: .black).cropped(to: extent)
        }

        // Blend with mask
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return inputImage
        }

        blendFilter.setValue(inputImage, forKey: kCIInputImageKey)
        blendFilter.setValue(background, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? inputImage
    }

    func render(_ image: CIImage, to pixelBuffer: CVPixelBuffer, enableAlpha: Bool = false) {
        // Use appropriate color space for alpha rendering
        let colorSpace: CGColorSpace
        if enableAlpha {
            // Use extended sRGB with alpha support
            colorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB) ?? CGColorSpaceCreateDeviceRGB()
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB()
        }

        ciContext.render(image, to: pixelBuffer, bounds: image.extent, colorSpace: colorSpace)
    }
}

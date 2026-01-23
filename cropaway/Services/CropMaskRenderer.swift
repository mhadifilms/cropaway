//
//  CropMaskRenderer.swift
//  cropaway
//

import Foundation
import CoreImage
import CoreGraphics

final class CropMaskRenderer: @unchecked Sendable {
    private let ciContext: CIContext

    init() {
        // Use Metal for GPU acceleration
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(
                mtlDevice: metalDevice,
                options: [
                    .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
                    .highQualityDownsample: true
                ]
            )
        } else {
            self.ciContext = CIContext(options: [
                .highQualityDownsample: true
            ])
        }
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
            return generateFreehandMask(points: state.freehandPoints, size: size)
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

    private func generateFreehandMask(points: [CGPoint], size: CGSize) -> CIImage {
        guard points.count >= 3 else {
            // Return full white mask if not enough points
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        let path = CGMutablePath()
        let firstPoint = points[0].denormalized(to: size)
        // Flip Y
        path.move(to: CGPoint(x: firstPoint.x, y: size.height - firstPoint.y))

        for point in points.dropFirst() {
            let pixelPoint = point.denormalized(to: size)
            path.addLine(to: CGPoint(x: pixelPoint.x, y: size.height - pixelPoint.y))
        }
        path.closeSubpath()

        return renderPathToMask(path, size: size)
    }

    // Thread-safe mask rendering using Core Graphics (no AppKit)
    private func renderPathToMask(_ path: CGPath, size: CGSize) -> CIImage {
        let width = Int(size.width)
        let height = Int(size.height)

        // Create grayscale bitmap context (thread-safe)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
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

    func render(_ image: CIImage, to pixelBuffer: CVPixelBuffer) {
        ciContext.render(image, to: pixelBuffer)
    }
}

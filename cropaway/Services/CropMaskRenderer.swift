//
//  CropMaskRenderer.swift
//  cropaway
//

import Foundation
import CoreImage
import CoreGraphics
import Metal

final class CropMaskRenderer: @unchecked Sendable {
    private let ciContext: CIContext

    // Reusable mask context to avoid memory pressure during export
    private var maskContext: CGContext?
    private var maskContextSize: CGSize = .zero

    private static let cleanKernel = CIColorKernel(source: """
    kernel vec4 cleanKernel(__sample s, float blackThreshold, float whiteThreshold) {
        float m = clamp(s.a, 0.0, 1.0);
        if (m < blackThreshold) { m = 0.0; }
        if (m > whiteThreshold) { m = 1.0; }
        return vec4(m, m, m, m);
    }
    """)

    private static let gammaKernel = CIColorKernel(source: """
    kernel vec4 gammaKernel(__sample s, float gamma) {
        float m = clamp(s.a, 0.0, 1.0);
        m = pow(m, gamma);
        return vec4(m, m, m, m);
    }
    """)

    private static let remapKernel = CIColorKernel(source: """
    kernel vec4 remapKernel(__sample s, float blackClip, float whiteClip) {
        float m = clamp(s.a, 0.0, 1.0);
        float denom = max(whiteClip - blackClip, 0.0001);
        m = clamp((m - blackClip) / denom, 0.0, 1.0);
        return vec4(m, m, m, m);
    }
    """)

    private static let mixKernel = CIColorKernel(source: """
    kernel vec4 mixKernel(__sample base, __sample processed, float amount) {
        float a = clamp(amount, 0.0, 1.0);
        float m = mix(base.a, processed.a, a);
        return vec4(m, m, m, m);
    }
    """)

    init() {
        // Use Metal for GPU acceleration with memory-efficient settings
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(
                mtlDevice: metalDevice,
                options: [
                    .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
                    .highQualityDownsample: true,
                    .cacheIntermediates: false
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
            existing.clear(CGRect(origin: .zero, size: size))
            return existing
        }

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
        size: CGSize,
        refinement: MaskRefinementParams = .default,
        guideImage: CIImage? = nil
    ) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)

        let baseMask: CIImage
        switch mode {
        case .rectangle:
            baseMask = generateRectangleMask(rect: state.cropRect, size: size)
        case .circle:
            baseMask = generateCircleMask(center: state.circleCenter, radius: state.circleRadius, size: size)
        case .freehand:
            baseMask = generateFreehandMask(pathData: state.freehandPathData, points: state.freehandPoints, size: size)
        case .ai:
            if let maskData = state.aiMaskData {
                baseMask = generateAIMask(maskData: maskData, size: size)
            } else {
                baseMask = CIImage(color: .white).cropped(to: extent)
            }
        }

        let normalized = normalizeMask(baseMask, mode: mode).cropped(to: extent)

        var sanitized = refinement
        sanitized.sanitize()
        guard !sanitized.isNeutral else {
            return normalized
        }

        return refineMask(
            normalized,
            params: sanitized,
            guideImage: guideImage,
            extent: extent
        )
    }

    func renderMaskImage(
        mode: CropMode,
        state: InterpolatedCropState,
        size: CGSize,
        refinement: MaskRefinementParams = .default,
        guideImage: CIImage? = nil
    ) -> CGImage? {
        let extent = CGRect(origin: .zero, size: size)
        let mask = generateMask(
            mode: mode,
            state: state,
            size: size,
            refinement: refinement,
            guideImage: guideImage
        )
        return ciContext.createCGImage(mask.cropped(to: extent), from: extent)
    }

    private func normalizeMask(_ image: CIImage, mode: CropMode) -> CIImage {
        let vectorFromAlpha = CIVector(x: 0, y: 0, z: 0, w: 1)
        let vectorFromRed = CIVector(x: 1, y: 0, z: 0, w: 0)
        let sourceVector = mode == .ai ? vectorFromAlpha : vectorFromRed

        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": sourceVector,
            "inputGVector": sourceVector,
            "inputBVector": sourceVector,
            "inputAVector": sourceVector,
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }

    private func refineMask(
        _ mask: CIImage,
        params: MaskRefinementParams,
        guideImage: CIImage?,
        extent: CGRect
    ) -> CIImage {
        var working = mask

        // 1) Clean black / white threshold crush
        working = applyCleanThresholds(working, cleanBlack: params.cleanBlack, cleanWhite: params.cleanWhite, extent: extent)

        // 2) Morphological operation
        working = applyMorphology(
            working,
            mode: params.mode,
            shape: params.shape,
            radius: params.radius,
            iterations: params.iterations,
            quality: params.quality,
            extent: extent
        )

        // 3) Edge-aware smoothing
        working = applyEdgeAwareSmoothing(working, sigma: params.smoothing, extent: extent)

        // Smart refine (guided filter) - optional automation stage
        working = applySmartRefine(working, strength: params.smartRefine, guideImage: guideImage, extent: extent)

        // 4) Denoise
        working = applyDenoise(working, strength: params.denoise, quality: params.quality, extent: extent)

        // 5) Blur
        working = applyGaussianBlur(working, sigma: params.blurRadius, extent: extent)

        // 6) In/Out ratio (alpha ramp bias)
        working = applyInOutRatio(working, ratio: params.inOutRatio, extent: extent)

        // 7) Black / white clip remap
        working = applyOutputClip(working, blackClip: params.blackClip, whiteClip: params.whiteClip, extent: extent)

        // 8) Post filter
        working = applyGaussianBlur(working, sigma: params.postFilter, extent: extent)

        return working.cropped(to: extent)
    }

    private func applyCleanThresholds(_ image: CIImage, cleanBlack: Double, cleanWhite: Double, extent: CGRect) -> CIImage {
        guard cleanBlack > 0 || cleanWhite > 0,
              let kernel = Self.cleanKernel else {
            return image
        }

        let black = Float((cleanBlack / 100.0).clamped(to: 0...0.5))
        let white = Float((1.0 - cleanWhite / 100.0).clamped(to: 0.5...1.0))

        guard let output = kernel.apply(extent: extent, arguments: [image, black, max(white, black + 0.0001)]) else {
            return image
        }

        return output
    }

    private func applyMorphology(
        _ image: CIImage,
        mode: MorphMode,
        shape: KernelShape,
        radius: Int,
        iterations: Int,
        quality: Quality,
        extent: CGRect
    ) -> CIImage {
        guard radius > 0 else { return image }

        let passCount = max(1, iterations)
        var working = image

        for _ in 0..<passCount {
            working = applyMorphMode(working, mode: mode, shape: shape, radius: Double(radius), extent: extent)

            if quality == .better && radius > 1 {
                working = applyMorphMode(working, mode: mode, shape: shape, radius: Double(radius) * 0.5, extent: extent)
            }
        }

        return working.cropped(to: extent)
    }

    private func applyMorphMode(
        _ image: CIImage,
        mode: MorphMode,
        shape: KernelShape,
        radius: Double,
        extent: CGRect
    ) -> CIImage {
        switch mode {
        case .grow:
            return applyDilate(image, shape: shape, radius: radius, extent: extent)
        case .shrink:
            return applyErode(image, shape: shape, radius: radius, extent: extent)
        case .open:
            let eroded = applyErode(image, shape: shape, radius: radius, extent: extent)
            return applyDilate(eroded, shape: shape, radius: radius, extent: extent)
        case .close:
            let dilated = applyDilate(image, shape: shape, radius: radius, extent: extent)
            return applyErode(dilated, shape: shape, radius: radius, extent: extent)
        }
    }

    private func applyDilate(_ image: CIImage, shape: KernelShape, radius: Double, extent: CGRect) -> CIImage {
        switch shape {
        case .circle:
            return applyFilter("CIMorphologyMaximum", input: image, parameters: ["inputRadius": radius], extent: extent)
        case .square:
            let size = max(1.0, floor(radius * 2.0 + 1.0))
            return applyFilter("CIMorphologyRectangleMaximum", input: image, parameters: ["inputWidth": size, "inputHeight": size], extent: extent)
        case .diamond:
            return applyDiamondMorph(image, radius: radius, isDilate: true, extent: extent)
        }
    }

    private func applyErode(_ image: CIImage, shape: KernelShape, radius: Double, extent: CGRect) -> CIImage {
        switch shape {
        case .circle:
            return applyFilter("CIMorphologyMinimum", input: image, parameters: ["inputRadius": radius], extent: extent)
        case .square:
            let size = max(1.0, floor(radius * 2.0 + 1.0))
            return applyFilter("CIMorphologyRectangleMinimum", input: image, parameters: ["inputWidth": size, "inputHeight": size], extent: extent)
        case .diamond:
            return applyDiamondMorph(image, radius: radius, isDilate: false, extent: extent)
        }
    }

    private func applyDiamondMorph(_ image: CIImage, radius: Double, isDilate: Bool, extent: CGRect) -> CIImage {
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let rotate = CGAffineTransform(translationX: -center.x, y: -center.y)
            .rotated(by: .pi / 4)
            .translatedBy(x: center.x, y: center.y)
        let unrotate = CGAffineTransform(translationX: -center.x, y: -center.y)
            .rotated(by: -.pi / 4)
            .translatedBy(x: center.x, y: center.y)

        let size = max(1.0, floor(radius * 2.0 + 1.0))
        let filterName = isDilate ? "CIMorphologyRectangleMaximum" : "CIMorphologyRectangleMinimum"

        let rotated = image
            .clampedToExtent()
            .transformed(by: rotate)

        let morphed = applyFilter(
            filterName,
            input: rotated,
            parameters: ["inputWidth": size, "inputHeight": size],
            extent: rotated.extent
        )

        return morphed.transformed(by: unrotate).cropped(to: extent)
    }

    private func applyEdgeAwareSmoothing(_ image: CIImage, sigma: Double, extent: CGRect) -> CIImage {
        guard sigma > 0 else { return image }

        let blurred = applyGaussianBlur(image, sigma: sigma, extent: extent)
        let edgeMask = applyFilter(
            "CIMorphologyGradient",
            input: image,
            parameters: ["inputRadius": max(1.0, sigma * 0.5)],
            extent: extent
        )

        return blendWithMask(foreground: blurred, background: image, mask: edgeMask, extent: extent)
    }

    private func applySmartRefine(_ image: CIImage, strength: Double, guideImage: CIImage?, extent: CGRect) -> CIImage {
        guard strength > 0,
              let guidedFilter = CIFilter(name: "CIGuidedFilter") else {
            return image
        }

        let strengthRatio = (strength / 100.0).clamped(to: 0...1)
        let radius = max(1.0, strength * 0.22)
        let epsilon = max(0.0005, 0.02 - strengthRatio * 0.018)

        guidedFilter.setValue(image, forKey: kCIInputImageKey)
        guidedFilter.setValue((guideImage ?? image).cropped(to: extent), forKey: "inputGuideImage")
        guidedFilter.setValue(radius, forKey: "inputRadius")
        guidedFilter.setValue(epsilon, forKey: "inputEpsilon")

        guard let guided = guidedFilter.outputImage?.cropped(to: extent) else {
            return image
        }

        return mix(base: image, processed: guided, amount: strengthRatio, extent: extent)
    }

    private func applyDenoise(_ image: CIImage, strength: Double, quality: Quality, extent: CGRect) -> CIImage {
        guard strength > 0 else { return image }

        let strengthRatio = (strength / 100.0).clamped(to: 0...1)
        var denoised = applyFilter("CIMedianFilter", input: image, parameters: [:], extent: extent)

        if quality == .better {
            denoised = applyFilter("CIMedianFilter", input: denoised, parameters: [:], extent: extent)
            denoised = applyFilter(
                "CINoiseReduction",
                input: denoised,
                parameters: [
                    "inputNoiseLevel": max(0.0, strengthRatio * 0.08),
                    "inputSharpness": max(0.0, 0.4 - strengthRatio * 0.2)
                ],
                extent: extent
            )
        }

        return mix(base: image, processed: denoised, amount: strengthRatio, extent: extent)
    }

    private func applyGaussianBlur(_ image: CIImage, sigma: Double, extent: CGRect) -> CIImage {
        guard sigma > 0 else { return image }
        return applyFilter("CIGaussianBlur", input: image, parameters: ["inputRadius": sigma], extent: extent)
    }

    private func applyInOutRatio(_ image: CIImage, ratio: Double, extent: CGRect) -> CIImage {
        guard abs(ratio) > 0.0001,
              let kernel = Self.gammaKernel else {
            return image
        }

        // Positive ratio expands edge transition outward (gamma < 1), negative contracts (gamma > 1)
        let gamma = Float(pow(2.0, -ratio))
        guard let output = kernel.apply(extent: extent, arguments: [image, gamma]) else {
            return image
        }

        return output
    }

    private func applyOutputClip(_ image: CIImage, blackClip: Double, whiteClip: Double, extent: CGRect) -> CIImage {
        guard blackClip > 0 || whiteClip < 100,
              let kernel = Self.remapKernel else {
            return image
        }

        let black = Float((blackClip / 100.0).clamped(to: 0...1))
        let white = Float((whiteClip / 100.0).clamped(to: 0...1))

        guard let output = kernel.apply(extent: extent, arguments: [image, black, max(white, black + 0.0001)]) else {
            return image
        }

        return output
    }

    private func blendWithMask(foreground: CIImage, background: CIImage, mask: CIImage, extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CIBlendWithMask") else {
            return foreground
        }

        filter.setValue(foreground, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        filter.setValue(mask, forKey: kCIInputMaskImageKey)

        return filter.outputImage?.cropped(to: extent) ?? foreground
    }

    private func mix(base: CIImage, processed: CIImage, amount: Double, extent: CGRect) -> CIImage {
        guard let kernel = Self.mixKernel,
              let output = kernel.apply(extent: extent, arguments: [base, processed, Float(amount)]) else {
            return processed
        }
        return output
    }

    private func applyFilter(_ name: String, input: CIImage, parameters: [String: Any], extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: name) else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        for (key, value) in parameters {
            filter.setValue(value, forKey: key)
        }

        return filter.outputImage?.cropped(to: extent) ?? input
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
        path.move(to: CGPoint(x: firstPos.x, y: size.height - firstPos.y))

        for i in 1..<vertices.count {
            addBezierSegment(to: path, from: vertices[i - 1], to: vertices[i], size: size)
        }

        addBezierSegment(to: path, from: vertices[vertices.count - 1], to: vertices[0], size: size)
        path.closeSubpath()

        return renderPathToMask(path, size: size)
    }

    private func addBezierSegment(to path: CGMutablePath, from: MaskVertex, to: MaskVertex, size: CGSize) {
        let fromPx = from.position.denormalized(to: size)
        let toPx = to.position.denormalized(to: size)

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
            let ctrl = CGPoint(
                x: fromPx.x + from.controlOut!.x * size.width,
                y: size.height - (fromPx.y + from.controlOut!.y * size.height)
            )
            let ctrl1 = CGPoint(
                x: fromFlipped.x + 2.0 / 3.0 * (ctrl.x - fromFlipped.x),
                y: fromFlipped.y + 2.0 / 3.0 * (ctrl.y - fromFlipped.y)
            )
            let ctrl2 = CGPoint(
                x: toFlipped.x + 2.0 / 3.0 * (ctrl.x - toFlipped.x),
                y: toFlipped.y + 2.0 / 3.0 * (ctrl.y - toFlipped.y)
            )
            path.addCurve(to: toFlipped, control1: ctrl1, control2: ctrl2)
        } else if hasToHandle {
            let ctrl = CGPoint(
                x: toPx.x + to.controlIn!.x * size.width,
                y: size.height - (toPx.y + to.controlIn!.y * size.height)
            )
            let ctrl1 = CGPoint(
                x: fromFlipped.x + 2.0 / 3.0 * (ctrl.x - fromFlipped.x),
                y: fromFlipped.y + 2.0 / 3.0 * (ctrl.y - fromFlipped.y)
            )
            let ctrl2 = CGPoint(
                x: toFlipped.x + 2.0 / 3.0 * (ctrl.x - toFlipped.x),
                y: toFlipped.y + 2.0 / 3.0 * (ctrl.y - toFlipped.y)
            )
            path.addCurve(to: toFlipped, control1: ctrl1, control2: ctrl2)
        } else {
            path.addLine(to: toFlipped)
        }
    }

    private func generateAIMask(maskData: Data?, size: CGSize) -> CIImage {
        guard let data = maskData else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        guard let (cgImage, maskWidth, maskHeight) = AIMaskResult.decodeMaskToImage(data) else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        }

        var maskImage = CIImage(cgImage: cgImage)

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

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

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

        let background: CIImage
        if enableAlpha {
            background = CIImage.clear.cropped(to: extent)
        } else {
            background = CIImage(color: .black).cropped(to: extent)
        }

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return inputImage
        }

        blendFilter.setValue(inputImage, forKey: kCIInputImageKey)
        blendFilter.setValue(background, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask.cropped(to: extent), forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage?.cropped(to: extent) ?? inputImage
    }

    func render(_ image: CIImage, to pixelBuffer: CVPixelBuffer, enableAlpha: Bool = false) {
        let colorSpace: CGColorSpace
        if enableAlpha {
            colorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB) ?? CGColorSpaceCreateDeviceRGB()
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB()
        }

        ciContext.render(image, to: pixelBuffer, bounds: image.extent, colorSpace: colorSpace)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

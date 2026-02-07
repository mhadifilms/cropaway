//
//  MaskedVideoPlayerView.swift
//  cropaway
//
//  Video player with Core Animation layer mask for alpha cropping

import SwiftUI
import AVKit

/// Video player that supports CALayer-based masking for alpha mode
struct MaskedVideoPlayerView: NSViewRepresentable {
    @Environment(VideoPlayerViewModel.self) private var playerVM: VideoPlayerViewModel

    let maskMode: CropMode
    let cropRect: CGRect
    let circleCenter: CGPoint
    let circleRadius: Double
    let freehandPoints: [CGPoint]
    let freehandPathData: Data?
    let aiMaskData: Data?
    let videoDisplaySize: CGSize

    func makeNSView(context: Context) -> MaskedPlayerContainerView {
        let containerView = MaskedPlayerContainerView()
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        return containerView
    }

    func updateNSView(_ nsView: MaskedPlayerContainerView, context: Context) {
        nsView.playerView.player = playerVM.player

        // Use videoDisplaySize for mask calculations (same as crop handles)
        // Don't use nsView.bounds which may not be updated yet
        let maskSize = videoDisplaySize
        let maskPath = createMaskPath(size: maskSize)
        nsView.updateMask(path: maskPath, aiMaskData: aiMaskData, size: maskSize)
    }

    private func createMaskPath(size: CGSize) -> CGPath? {
        guard size.width > 0 && size.height > 0 else { return nil }

        // CALayer uses bottom-left origin (Y increases upward), but SwiftUI/crop coordinates
        // use top-left origin (Y increases downward). We need to flip Y coordinates.
        // For a normalized Y value, flipped Y = 1 - Y
        // For a pixel Y value, flipped Y = size.height - Y

        switch maskMode {
        case .rectangle:
            let pixelRect = cropRect.denormalized(to: size)
            // Flip Y: new origin.y = size.height - (origin.y + height)
            let flippedRect = CGRect(
                x: pixelRect.origin.x,
                y: size.height - pixelRect.origin.y - pixelRect.height,
                width: pixelRect.width,
                height: pixelRect.height
            )
            return CGPath(rect: flippedRect, transform: nil)

        case .circle:
            let center = circleCenter.denormalized(to: size)
            // Flip Y coordinate for center
            let flippedCenter = CGPoint(x: center.x, y: size.height - center.y)
            let radius = circleRadius * min(size.width, size.height)
            let circleRect = CGRect(
                x: flippedCenter.x - radius,
                y: flippedCenter.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            return CGPath(ellipseIn: circleRect, transform: nil)

        case .freehand:
            // Try bezier path from vertex data
            if let data = freehandPathData,
               let vertices = try? JSONDecoder().decode([MaskVertex].self, from: data),
               vertices.count >= 3 {
                return buildBezierPath(vertices: vertices, size: size)
            }
            // Fallback to simple polygon
            guard freehandPoints.count >= 3 else { return nil }
            let path = CGMutablePath()
            let first = freehandPoints[0].denormalized(to: size)
            // Flip Y coordinate
            path.move(to: CGPoint(x: first.x, y: size.height - first.y))
            for point in freehandPoints.dropFirst() {
                let denorm = point.denormalized(to: size)
                path.addLine(to: CGPoint(x: denorm.x, y: size.height - denorm.y))
            }
            path.closeSubpath()
            return path

        case .ai:
            // AI mode uses image-based mask, return nil for path
            return nil
        }
    }

    private func buildBezierPath(vertices: [MaskVertex], size: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard vertices.count >= 3 else { return path }

        // Flip Y coordinate for CALayer coordinate system
        let firstPos = vertices[0].position.denormalized(to: size)
        path.move(to: CGPoint(x: firstPos.x, y: size.height - firstPos.y))

        for i in 1..<vertices.count {
            addBezierSegment(to: path, from: vertices[i-1], to: vertices[i], size: size)
        }

        // Close the path
        addBezierSegment(to: path, from: vertices[vertices.count - 1], to: vertices[0], size: size)
        path.closeSubpath()

        return path
    }

    private func addBezierSegment(to path: CGMutablePath, from: MaskVertex, to: MaskVertex, size: CGSize) {
        let fromPx = from.position.denormalized(to: size)
        let toPx = to.position.denormalized(to: size)

        // Flip Y coordinates for CALayer coordinate system (bottom-left origin)
        let fromFlipped = CGPoint(x: fromPx.x, y: size.height - fromPx.y)
        let toFlipped = CGPoint(x: toPx.x, y: size.height - toPx.y)

        let hasFromHandle = from.controlOut != nil
        let hasToHandle = to.controlIn != nil

        if hasFromHandle && hasToHandle {
            // Control points: add offset to flipped position, but also flip the Y offset
            let ctrl1 = CGPoint(
                x: fromFlipped.x + from.controlOut!.x * size.width,
                y: fromFlipped.y - from.controlOut!.y * size.height  // Flip Y offset
            )
            let ctrl2 = CGPoint(
                x: toFlipped.x + to.controlIn!.x * size.width,
                y: toFlipped.y - to.controlIn!.y * size.height  // Flip Y offset
            )
            path.addCurve(to: toFlipped, control1: ctrl1, control2: ctrl2)
        } else if hasFromHandle {
            let ctrl = CGPoint(
                x: fromFlipped.x + from.controlOut!.x * size.width,
                y: fromFlipped.y - from.controlOut!.y * size.height  // Flip Y offset
            )
            path.addQuadCurve(to: toFlipped, control: ctrl)
        } else if hasToHandle {
            let ctrl = CGPoint(
                x: toFlipped.x + to.controlIn!.x * size.width,
                y: toFlipped.y - to.controlIn!.y * size.height  // Flip Y offset
            )
            path.addQuadCurve(to: toFlipped, control: ctrl)
        } else {
            path.addLine(to: toFlipped)
        }
    }
}

/// Container NSView that uses AVPlayerLayer directly for maskable video
class MaskedPlayerContainerView: NSView {
    // Use AVPlayerLayer directly instead of AVPlayerView for proper masking
    let playerLayer: AVPlayerLayer
    private var maskLayer: CAShapeLayer?
    private var imageMaskLayer: CALayer?

    // Expose a fake playerView property that forwards player assignment
    var playerView: PlayerProxy { PlayerProxy(layer: playerLayer) }

    override init(frame: NSRect) {
        playerLayer = AVPlayerLayer()
        // Use .resize to fill the frame exactly - the frame is already calculated
        // with correct aspect ratio by the parent view
        playerLayer.videoGravity = .resize

        super.init(frame: frame)

        wantsLayer = true
        layer?.addSublayer(playerLayer)

        print("[MaskedPlayerContainerView] Created with AVPlayerLayer")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        // Update player layer frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds

        // Update mask layer frame
        if let mask = maskLayer {
            mask.frame = bounds
        }
        if let imgMask = imageMaskLayer {
            imgMask.frame = bounds
        }
        CATransaction.commit()

        print("[MaskedPlayerContainerView] layout: bounds=\(bounds), mask=\(maskLayer != nil)")
    }

    func updateMask(path: CGPath?, aiMaskData: Data?, size: CGSize) {
        print("[MaskedPlayerContainerView] updateMask: size=\(size), hasPath=\(path != nil), hasAIData=\(aiMaskData != nil)")

        guard size.width > 0 && size.height > 0 else {
            print("[MaskedPlayerContainerView] updateMask: size invalid, skipping")
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Ensure playerLayer frame matches the expected size
        let layerFrame = CGRect(origin: .zero, size: size)
        playerLayer.frame = layerFrame

        // Handle AI mask (image-based)
        if let maskData = aiMaskData {
            // Remove shape mask
            maskLayer = nil

            // Create or update image mask
            if let (cgImage, w, h) = AIMaskResult.decodeMaskToImage(maskData) {
                print("[MaskedPlayerContainerView] AI mask decoded: \(w)x\(h), layerFrame: \(layerFrame)")
                if imageMaskLayer == nil {
                    imageMaskLayer = CALayer()
                    // Use .resize to stretch mask to exactly match the video layer
                    imageMaskLayer?.contentsGravity = .resize
                }
                imageMaskLayer?.frame = layerFrame
                imageMaskLayer?.contents = cgImage
                // Flip the image vertically to match CALayer coordinate system
                // CGImage origin is top-left, but CALayer uses bottom-left origin
                imageMaskLayer?.transform = CATransform3DMakeScale(1, -1, 1)
                imageMaskLayer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                playerLayer.mask = imageMaskLayer
                print("[MaskedPlayerContainerView] AI mask applied to playerLayer (with Y-flip)")
            } else {
                print("[MaskedPlayerContainerView] AI mask decode FAILED")
                playerLayer.mask = nil
            }
            CATransaction.commit()
            return
        }

        // Handle shape-based mask
        imageMaskLayer = nil

        guard let path = path else {
            // No mask - clear any existing mask
            print("[MaskedPlayerContainerView] Clearing mask (no path)")
            playerLayer.mask = nil
            maskLayer = nil
            CATransaction.commit()
            return
        }

        // Create or update shape mask layer
        if maskLayer == nil {
            maskLayer = CAShapeLayer()
            maskLayer?.fillColor = NSColor.white.cgColor
        }

        maskLayer?.frame = layerFrame
        maskLayer?.path = path
        playerLayer.mask = maskLayer

        print("[MaskedPlayerContainerView] Shape mask applied: \(path.boundingBox)")
        CATransaction.commit()
    }
}

/// Proxy to allow setting player on AVPlayerLayer
class PlayerProxy {
    let layer: AVPlayerLayer

    init(layer: AVPlayerLayer) {
        self.layer = layer
    }

    var player: AVPlayer? {
        get { layer.player }
        set { layer.player = newValue }
    }
}

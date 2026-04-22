//
//  MaskedVideoPlayerView.swift
//  cropaway
//
//  Video player with Core Animation layer mask for alpha cropping

import SwiftUI
import AVKit

/// Video player that supports CALayer-based masking for alpha mode
struct MaskedVideoPlayerView: NSViewRepresentable {
    @EnvironmentObject var playerVM: VideoPlayerViewModel

    private static let previewMaskRenderer = CropMaskRenderer()

    let maskMode: CropMode
    let cropRect: CGRect
    let circleCenter: CGPoint
    let circleRadius: Double
    let freehandPoints: [CGPoint]
    let freehandPathData: Data?
    let aiMaskData: Data?
    let maskSmoothness: Double
    let maskRadius: Double
    let maskDenoise: Double
    let videoDisplaySize: CGSize

    func makeNSView(context: Context) -> MaskedPlayerContainerView {
        let containerView = MaskedPlayerContainerView()
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        return containerView
    }

    func updateNSView(_ nsView: MaskedPlayerContainerView, context: Context) {
        nsView.playerView.player = playerVM.player

        guard videoDisplaySize.isValid else {
            nsView.updateMask(maskImage: nil, size: .zero)
            return
        }

        let state = InterpolatedCropState(
            cropRect: cropRect,
            edgeInsets: EdgeInsets(),
            circleCenter: circleCenter,
            circleRadius: circleRadius,
            freehandPoints: freehandPoints,
            freehandPathData: freehandPathData,
            aiMaskData: aiMaskData,
            aiBoundingBox: .zero
        )

        let maskImage = Self.previewMaskRenderer.generateMaskImage(
            mode: maskMode,
            state: state,
            size: videoDisplaySize,
            smoothness: maskSmoothness,
            radius: maskRadius,
            denoise: maskDenoise
        )

        nsView.updateMask(maskImage: maskImage, size: videoDisplaySize)
    }
}

/// Container NSView that uses AVPlayerLayer directly for maskable video
class MaskedPlayerContainerView: NSView {
    // Use AVPlayerLayer directly instead of AVPlayerView for proper masking
    let playerLayer: AVPlayerLayer
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
        if let imgMask = imageMaskLayer {
            imgMask.frame = bounds
        }
        CATransaction.commit()
    }

    func updateMask(maskImage: CGImage?, size: CGSize) {
        guard size.width > 0 && size.height > 0 else {
            playerLayer.mask = nil
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Ensure playerLayer frame matches the expected size
        let layerFrame = CGRect(origin: .zero, size: size)
        playerLayer.frame = layerFrame

        guard let maskImage else {
            playerLayer.mask = nil
            CATransaction.commit()
            return
        }

        if imageMaskLayer == nil {
            imageMaskLayer = CALayer()
            imageMaskLayer?.contentsGravity = .resize
        }

        imageMaskLayer?.frame = layerFrame
        imageMaskLayer?.contents = maskImage
        // Flip image to match CALayer coordinate system.
        imageMaskLayer?.transform = CATransform3DMakeScale(1, -1, 1)
        imageMaskLayer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        playerLayer.mask = imageMaskLayer
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

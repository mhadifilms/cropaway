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
    let maskRefinement: MaskRefinementParams

    private static let renderer = CropMaskRenderer()

    func makeNSView(context: Context) -> MaskedPlayerContainerView {
        let containerView = MaskedPlayerContainerView()
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        return containerView
    }

    func updateNSView(_ nsView: MaskedPlayerContainerView, context: Context) {
        nsView.playerView.player = playerVM.player

        let maskSize = videoDisplaySize
        guard maskSize.width > 0, maskSize.height > 0 else {
            nsView.updateMask(maskImage: nil, size: .zero)
            return
        }

        let state = InterpolatedCropState(
            cropRect: cropRect,
            edgeInsets: .init(),
            circleCenter: circleCenter,
            circleRadius: circleRadius,
            freehandPoints: freehandPoints,
            freehandPathData: freehandPathData,
            aiMaskData: aiMaskData,
            aiBoundingBox: .zero,
            maskRefinement: maskRefinement
        )

        let maskImage = Self.renderer.renderMaskImage(
            mode: maskMode,
            state: state,
            size: maskSize,
            refinement: maskRefinement,
            guideImage: nil
        )

        nsView.updateMask(maskImage: maskImage, size: maskSize)
    }
}

/// Container NSView that uses AVPlayerLayer directly for maskable video
class MaskedPlayerContainerView: NSView {
    let playerLayer: AVPlayerLayer
    private var imageMaskLayer: CALayer?

    // Expose a fake playerView property that forwards player assignment
    var playerView: PlayerProxy { PlayerProxy(layer: playerLayer) }

    override init(frame: NSRect) {
        playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resize

        super.init(frame: frame)

        wantsLayer = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        imageMaskLayer?.frame = bounds
        CATransaction.commit()
    }

    func updateMask(maskImage: CGImage?, size: CGSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if size.width > 0, size.height > 0 {
            playerLayer.frame = CGRect(origin: .zero, size: size)
        }

        guard let maskImage else {
            playerLayer.mask = nil
            imageMaskLayer = nil
            CATransaction.commit()
            return
        }

        if imageMaskLayer == nil {
            imageMaskLayer = CALayer()
            imageMaskLayer?.contentsGravity = .resize
        }

        imageMaskLayer?.frame = playerLayer.frame
        imageMaskLayer?.contents = maskImage
        imageMaskLayer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
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

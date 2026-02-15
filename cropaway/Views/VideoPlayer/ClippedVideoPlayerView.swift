//
//  ClippedVideoPlayerView.swift
//  cropaway
//
//  Video player that clips to show only a portion of the video (for preserve size OFF mode)

import SwiftUI
import AVKit

/// Video player that shows only a clipped portion of the video
/// Used when Preserve Size is OFF to zoom in on the cropped region
struct ClippedVideoPlayerView: NSViewRepresentable {
    @EnvironmentObject var playerVM: VideoPlayerViewModel

    /// The portion of the video to show (normalized 0-1 coordinates)
    let cropRect: CGRect
    /// The size of the visible frame (the clipped output size)
    let frameSize: CGSize

    func makeNSView(context: Context) -> ClippedPlayerContainerView {
        let containerView = ClippedPlayerContainerView()
        return containerView
    }

    func updateNSView(_ nsView: ClippedPlayerContainerView, context: Context) {
        nsView.playerLayer.player = playerVM.player
        // Pass the exact frameSize we want - don't rely on bounds
        nsView.configure(cropRect: cropRect, frameSize: frameSize)
    }
}

/// Container NSView that uses AVPlayerLayer with a mask to show only the cropped region
class ClippedPlayerContainerView: NSView {
    let playerLayer: AVPlayerLayer
    private let maskLayer: CALayer
    private var currentCropRect: CGRect = .zero
    private var currentFrameSize: CGSize = .zero

    override init(frame: NSRect) {
        playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resize

        maskLayer = CALayer()
        maskLayer.backgroundColor = NSColor.white.cgColor

        super.init(frame: frame)

        wantsLayer = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(cropRect: CGRect, frameSize: CGSize) {
        guard frameSize.width > 0 && frameSize.height > 0 else {
            print("[ClippedVideoPlayerView] ERROR: Invalid frameSize: \(frameSize)")
            return
        }
        guard cropRect.width > 0 && cropRect.height > 0 else {
            print("[ClippedVideoPlayerView] ERROR: Invalid cropRect: \(cropRect)")
            return
        }

        currentCropRect = cropRect
        currentFrameSize = frameSize

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // The frameSize is the size of the cropped region we want to display
        // We need to calculate how big the full video would be at this scale
        let fullVideoWidth = frameSize.width / cropRect.width
        let fullVideoHeight = frameSize.height / cropRect.height

        // Position the player layer so the crop region starts at (0,0) in view coordinates
        // offsetX/Y are negative values that shift the video left/up
        let offsetX = -cropRect.origin.x * fullVideoWidth
        let offsetY = -cropRect.origin.y * fullVideoHeight

        playerLayer.frame = CGRect(
            x: offsetX,
            y: offsetY,
            width: fullVideoWidth,
            height: fullVideoHeight
        )

        // The mask must be in playerLayer's coordinate system (bounds), not the view's
        // Since playerLayer is offset by (offsetX, offsetY), the visible area in the view's
        // (0,0) to (frameSize) maps to playerLayer's (-offsetX, -offsetY) to (-offsetX+frameSize)
        maskLayer.frame = CGRect(
            x: -offsetX,
            y: -offsetY,
            width: frameSize.width,
            height: frameSize.height
        )
        playerLayer.mask = maskLayer

        CATransaction.commit()

        let frameAspect = frameSize.width / frameSize.height
        let _ = (cropRect.width * 16) / (cropRect.height * 9) // Assuming 16:9 video
        print("[ClippedVideoPlayerView] frameSize=\(frameSize) (aspect: \(String(format: "%.3f", frameAspect))), cropRect=\(cropRect), fullVideo=\(fullVideoWidth)x\(fullVideoHeight), bounds=\(bounds)")
    }
}

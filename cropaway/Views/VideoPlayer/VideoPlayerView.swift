//
//  VideoPlayerView.swift
//  cropaway
//

import SwiftUI
import AVKit

struct VideoPlayerView: NSViewRepresentable {
    @EnvironmentObject var playerVM: VideoPlayerViewModel

    /// When true, video fills frame exactly (may distort if frame doesn't match video aspect ratio)
    /// When false (default), video maintains aspect ratio with letterboxing if needed
    var fillFrame: Bool = false

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false
        playerView.allowsPictureInPicturePlayback = false
        playerView.videoGravity = fillFrame ? .resize : .resizeAspect
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = playerVM.player
        // Update gravity in case fillFrame changed
        nsView.videoGravity = fillFrame ? .resize : .resizeAspect
    }
}

#Preview {
    VideoPlayerView()
        .environmentObject(VideoPlayerViewModel())
        .frame(width: 640, height: 360)
}

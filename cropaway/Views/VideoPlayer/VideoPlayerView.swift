//
//  VideoPlayerView.swift
//  cropaway
//

import SwiftUI
import AVKit

struct VideoPlayerView: NSViewRepresentable {
    @EnvironmentObject var playerVM: VideoPlayerViewModel

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false
        playerView.allowsPictureInPicturePlayback = false
        playerView.videoGravity = .resizeAspect
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = playerVM.player
    }
}

#Preview {
    VideoPlayerView()
        .environmentObject(VideoPlayerViewModel())
        .frame(width: 640, height: 360)
}

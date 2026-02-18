//
//  TimelineEditorView.swift
//  cropaway
//
//  PHASE 7: Timeline-first UI - Center panel with preview + timeline
//

import SwiftUI

/// Center panel combining video preview, playback controls, and timeline
/// Timeline is ALWAYS visible (not an optional bottom panel)
struct TimelineEditorView: View {
    @Environment(VideoPlayerViewModel.self) private var playerVM
    @Environment(TimelineViewModel.self) private var timelineVM
    @Environment(CropEditorViewModel.self) private var cropEditorVM
    @Environment(KeyframeViewModel.self) private var keyframeVM
    
    @Binding var viewScale: CGFloat
    @Binding var isPreviewMode: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Video preview (top)
            videoPreviewSection
            
            Divider()
            
            // Playback controls
            playbackControlsSection
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            Divider()
            
            // Timeline (bottom - always visible)
            timelineSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var videoPreviewSection: some View {
        GeometryReader { geometry in
            VideoPlayerView()
                .environment(playerVM)
                .environment(cropEditorVM)
                .environment(keyframeVM)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxHeight: .infinity)
        .background(Color.black)
    }
    
    @ViewBuilder
    private var playbackControlsSection: some View {
        HStack(spacing: 20) {
            // Playback buttons
            HStack(spacing: 8) {
                Button(action: { playerVM.seek(to: max(0, playerVM.currentTime - 5)) }) {
                    Image(systemName: "gobackward.5")
                }
                .help("Skip Backward 5s")
                
                Button(action: { playerVM.togglePlayPause() }) {
                    Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                .help(playerVM.isPlaying ? "Pause (Space)" : "Play (Space)")
                
                Button(action: { playerVM.seek(to: min(playerVM.duration, playerVM.currentTime + 5)) }) {
                    Image(systemName: "goforward.5")
                }
                .help("Skip Forward 5s")
            }
            .buttonStyle(.borderless)
            
            Spacer()
            
            // Time display
            Text(formatTime(playerVM.currentTime) + " / " + formatTime(playerVM.duration))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Timeline controls
            HStack(spacing: 8) {
                Button(action: { timelineVM.setInPoint() }) {
                    Image(systemName: "arrow.down.left.square")
                }
                .keyboardShortcut("i", modifiers: [])
                .help("Set In Point (I)")
                
                Button(action: { timelineVM.setOutPoint() }) {
                    Image(systemName: "arrow.down.right.square")
                }
                .keyboardShortcut("o", modifiers: [])
                .help("Set Out Point (O)")
                
                Button(action: { timelineVM.clearInOutPoints() }) {
                    Image(systemName: "xmark.circle")
                }
                .help("Clear In/Out Points")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Divider(),
            alignment: .bottom
        )
    }
    
    @ViewBuilder
    private var timelineSection: some View {
        if timelineVM.activeTimeline != nil {
            MultiTrackTimelineView(timelineViewModel: timelineVM)
                .environment(timelineVM)
                .frame(height: 250)
        } else {
            emptyTimelineView
        }
    }
    
    @ViewBuilder
    private var emptyTimelineView: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Active Sequence")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Create a new sequence or select one from the sidebar")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1.0)) * 30)
        return String(format: "%d:%02d:%02d", mins, secs, frames)
    }
}

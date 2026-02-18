//
//  TrackHeaderView.swift
//  cropaway
//
//  Created by Claude Code for Multi-Track Timeline
//

import SwiftUI

struct TrackHeaderView: View {
    @Bindable var track: Track
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 8) {
            // Track name
            TextField("Track Name", text: $track.name)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(width: 80)
            
            Spacer()
            
            // Track controls based on media type
            if track.mediaType == .video {
                // Hide/Show toggle
                Button(action: { track.isHidden.toggle() }) {
                    Image(systemName: track.isHidden ? "eye.slash" : "eye")
                        .foregroundStyle(track.isHidden ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .help(track.isHidden ? "Show track" : "Hide track")
            } else {
                // Mute toggle for audio
                Button(action: { track.isMuted.toggle() }) {
                    Image(systemName: track.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .foregroundStyle(track.isMuted ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .help(track.isMuted ? "Unmute track" : "Mute track")
            }
            
            // Lock toggle
            Button(action: { track.isLocked.toggle() }) {
                Image(systemName: track.isLocked ? "lock" : "lock.open")
                    .foregroundStyle(track.isLocked ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help(track.isLocked ? "Unlock track" : "Lock track")
            
            // Move up/down buttons
            if let onMoveUp = onMoveUp {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .help("Move track up")
            }
            
            if let onMoveDown = onMoveDown {
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .help("Move track down")
            }
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Delete track")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .frame(height: 30)
    }
}

#Preview {
    @Previewable @State var track = Track(
        name: "Video 1",
        clips: [],
        mediaType: .video,
        verticalOrder: 0
    )
    
    TrackHeaderView(
        track: track,
        onDelete: {},
        onMoveUp: {},
        onMoveDown: {}
    )
    .frame(width: 250)
}

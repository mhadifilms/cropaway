//
//  TrackRowView.swift
//  cropaway
//
//  Created by Claude Code for Multi-Track Timeline
//

import SwiftUI

struct TrackRowView: View {
    @Bindable var track: Track
    let timelineViewModel: TimelineViewModel
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Track header
            TrackHeaderView(
                track: track,
                onDelete: onDelete,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            
            Divider()
            
            // Track clips area
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    Rectangle()
                        .fill(trackBackgroundColor)
                    
                    // Clips
                    ForEach(track.clips) { clip in
                        clipView(for: clip, in: geometry.size.width)
                    }
                }
            }
            .frame(height: trackHeight)
        }
    }
    
    private var trackBackgroundColor: Color {
        if track.isLocked {
            return Color(NSColor.controlBackgroundColor).opacity(0.5)
        } else if track.isHidden || track.isMuted {
            return Color(NSColor.controlBackgroundColor).opacity(0.3)
        } else {
            return Color(NSColor.controlBackgroundColor).opacity(0.8)
        }
    }
    
    private var trackHeight: CGFloat {
        track.height  // PHASE 10: Use adjustable track height
    }
    
    @ViewBuilder
    private func clipView(for clip: TimelineClip, in totalWidth: CGFloat) -> some View {
        // Calculate cumulative position of clips in track
        let clipsBeforeThis = track.clips.prefix(while: { $0.id != clip.id })
        let positionInTrack = clipsBeforeThis.reduce(0.0) { $0 + $1.trimmedDuration }
        
        // Calculate total duration of all clips in track
        let trackDuration = track.clips.reduce(0.0) { $0 + $1.trimmedDuration }
        let duration = max(trackDuration, 1.0)
        
        // Calculate position and width
        let xPosition = (positionInTrack / duration) * totalWidth
        let clipWidth = (clip.trimmedDuration / duration) * totalWidth
        
        Rectangle()
            .fill(clipColor(for: clip))
            .frame(width: clipWidth, height: trackHeight - 8)
            .overlay(
                Text(clip.videoItem?.fileName ?? "Clip")
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundColor(.white)
                    .padding(4)
                ,
                alignment: .topLeading
            )
            .overlay(
                Rectangle()
                    .stroke(isSelected(clip) ? Color.blue : Color.gray.opacity(0.5), lineWidth: isSelected(clip) ? 2 : 1)
            )
            .position(x: xPosition + clipWidth / 2, y: (trackHeight - 8) / 2)
            .onTapGesture {
                // PHASE 8: Prevent selection if track is locked
                guard !track.isLocked else { return }
                timelineViewModel.selectClip(id: clip.id)
            }
            .contextMenu {
                // PHASE 10: Color label menu
                Menu("Color Label") {
                    ForEach(ClipColorLabel.allCases, id: \.self) { label in
                        Button(action: {
                            clip.colorLabel = label
                        }) {
                            HStack {
                                if clip.colorLabel == label {
                                    Image(systemName: "checkmark")
                                }
                                Text(label.rawValue)
                                if label != .none {
                                    Circle()
                                        .fill(Color(label.color))
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
            }
            .allowsHitTesting(!track.isLocked)  // PHASE 8: Disable interactions when locked
    }
    
    private func clipColor(for clip: TimelineClip) -> Color {
        // PHASE 10: Use color label if set
        if clip.colorLabel != .none {
            return Color(clip.colorLabel.color)
        }
        
        if let video = clip.videoItem {
            // Use a deterministic color based on video ID
            let hue = Double(video.id.hashValue % 360) / 360.0
            return Color(hue: hue, saturation: 0.6, brightness: 0.7)
        }
        return Color.gray
    }
    
    private func isSelected(_ clip: TimelineClip) -> Bool {
        timelineViewModel.selectedClip?.id == clip.id
    }
}

#Preview {
    @Previewable @State var timelineVM = TimelineViewModel()
    @Previewable @State var track = Track(
        name: "Video 1",
        clips: [],
        mediaType: .video,
        verticalOrder: 0
    )
    
    TrackRowView(
        track: track,
        timelineViewModel: timelineVM,
        onDelete: {},
        onMoveUp: nil,
        onMoveDown: {}
    )
    .frame(height: 110)
}

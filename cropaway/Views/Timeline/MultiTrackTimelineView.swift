//
//  MultiTrackTimelineView.swift
//  cropaway
//
//  Created by Claude Code for Multi-Track Timeline
//

import SwiftUI

struct MultiTrackTimelineView: View {
    @Bindable var timelineViewModel: TimelineViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Timeline header with controls
            timelineHeader
            
            Divider()
            
            // Scrollable track list
            if let timeline = timelineViewModel.activeTimeline {
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        ForEach(Array(timeline.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRowView(
                                track: track,
                                timelineViewModel: timelineViewModel,
                                onDelete: {
                                    timelineViewModel.deleteTrack(track)
                                },
                                onMoveUp: index > 0 ? {
                                    timelineViewModel.moveTrack(track, direction: .up)
                                } : nil,
                                onMoveDown: index < timeline.tracks.count - 1 ? {
                                    timelineViewModel.moveTrack(track, direction: .down)
                                } : nil
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    @ViewBuilder
    private var timelineHeader: some View {
        HStack {
            Text("Timeline")
                .font(.headline)
            
            Spacer()
            
            // Add track button with glass effect
            Menu {
                Button("Add Video Track") {
                    timelineViewModel.addVideoTrack()
                }
                Button("Add Audio Track") {
                    timelineViewModel.addAudioTrack()
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .help("Add Track")
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
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Timeline")
                .font(.headline)
            
            Text("Create a timeline to start editing")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Create Timeline") {
                timelineViewModel.createNewTimeline()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

#Preview {
    @Previewable @State var timelineVM = TimelineViewModel()
    
    MultiTrackTimelineView(timelineViewModel: timelineVM)
        .frame(height: 400)
}

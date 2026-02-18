//
//  SequencesTabView.swift
//  cropaway
//
//  Created by Claude Code for Project Sidebar
//

import SwiftUI

struct SequencesTabView: View {
    @Bindable var timelineViewModel: TimelineViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sequences")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Sequences list
            if timelineViewModel.timelines.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(timelineViewModel.timelines) { timeline in
                            sequenceRow(timeline)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            
            Text("No Sequences")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Create a new sequence to start editing")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    @ViewBuilder
    private func sequenceRow(_ timeline: Timeline) -> some View {
        HStack(spacing: 8) {
            // Active indicator
            Circle()
                .fill(isActive(timeline) ? Color.blue : Color.clear)
                .frame(width: 6, height: 6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(timeline.name)
                    .font(.subheadline)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Label("\(timeline.tracks.count)", systemImage: "square.stack.3d.up")
                    Label(formatDuration(timeline.totalDuration), systemImage: "clock")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Delete button
            Button(action: {
                timelineViewModel.deleteTimeline(timeline)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .opacity(0.5)
        }
        .padding(8)
        .background(isActive(timeline) ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            timelineViewModel.setActiveTimeline(timeline)
        }
    }
    
    private func isActive(_ timeline: Timeline) -> Bool {
        timelineViewModel.activeTimeline?.id == timeline.id
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    @Previewable @State var timelineVM = TimelineViewModel()
    
    SequencesTabView(timelineViewModel: timelineVM)
        .frame(width: 220, height: 400)
}

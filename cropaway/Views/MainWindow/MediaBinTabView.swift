//
//  MediaBinTabView.swift
//  cropaway
//
//  Created by Claude Code for Project Sidebar
//

import SwiftUI

struct MediaBinTabView: View {
    @Bindable var projectViewModel: ProjectViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Media Bin")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Video list
            if projectViewModel.videos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(projectViewModel.videos) { video in
                            videoRow(video)
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
            Image(systemName: "video.stack")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            
            Text("No Media")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Import videos to add them to your project")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    @ViewBuilder
    private func videoRow(_ video: VideoItem) -> some View {
        HStack(spacing: 8) {
            // Thumbnail
            if let thumbnail = video.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 48, height: 32)
                    .overlay(
                        Image(systemName: "video")
                            .foregroundStyle(.secondary)
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(video.fileName)
                    .font(.caption)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text("\(video.metadata.width)×\(video.metadata.height)")
                    Text(formatDuration(video.metadata.duration))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(isSelected(video) ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            projectViewModel.selectedVideo = video
        }
        .onDrag {
            // Enable drag from media bin to timeline
            NSItemProvider(object: video.sourceURL as NSURL)
        }
    }
    
    private func isSelected(_ video: VideoItem) -> Bool {
        projectViewModel.selectedVideo?.id == video.id
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    @Previewable @State var projectVM = ProjectViewModel()
    
    MediaBinTabView(projectViewModel: projectVM)
        .frame(width: 220, height: 400)
}

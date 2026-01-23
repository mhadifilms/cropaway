//
//  VideoSidebarView.swift
//  cropaway
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoSidebarView: View {
    @EnvironmentObject var projectVM: ProjectViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Video list with multi-selection support
            List(selection: $projectVM.selectedVideoIDs) {
                ForEach(projectVM.videos) { video in
                    VideoRowView(video: video)
                        .tag(video.id)
                        .contextMenu { videoContextMenu(for: video) }
                }
                .onDelete(perform: projectVM.removeVideos)
            }
            .listStyle(.sidebar)
            .onChange(of: projectVM.selectedVideoIDs) { _, newSelection in
                // Update primary selection when multi-selection changes
                if newSelection.count == 1, let id = newSelection.first {
                    projectVM.selectedVideo = projectVM.videos.first { $0.id == id }
                } else if newSelection.isEmpty {
                    // Deselect primary as well when multi-select is cleared
                    projectVM.selectedVideo = nil
                } else if let currentId = projectVM.selectedVideo?.id, !newSelection.contains(currentId) {
                    // If current selection not in new set, pick first from set
                    projectVM.selectedVideo = projectVM.videos.first { newSelection.contains($0.id) }
                }
            }
            .onTapGesture {
                // Clicking empty area deselects
                if projectVM.selectedVideoIDs.isEmpty {
                    projectVM.selectedVideo = nil
                }
            }

            Divider()

            // Bottom toolbar
            HStack(alignment: .center, spacing: 8) {
                Button(action: openFilePicker) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Add videos (Cmd+O)")

                Spacer()

                Text("\(projectVM.videos.count) clip\(projectVM.videos.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: removeSelectedVideos) {
                    Image(systemName: "minus")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Remove selected (Cmd+Delete)")
                .disabled(projectVM.selectedVideoIDs.isEmpty && projectVM.selectedVideo == nil)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(height: 36)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openFilePicker) {
                    Label("Add Video", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func videoContextMenu(for video: VideoItem) -> some View {
        Button("Export...") {
            projectVM.selectedVideo = video
            NotificationCenter.default.post(name: .exportVideo, object: nil)
        }

        if projectVM.selectedVideoIDs.count > 1 {
            Button("Export Selected (\(projectVM.selectedVideoIDs.count))...") {
                NotificationCenter.default.post(name: .exportAllVideos, object: nil)
            }
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([video.sourceURL])
        }

        Divider()

        Button("Remove", role: .destructive) {
            projectVM.removeVideo(video)
        }

        if projectVM.selectedVideoIDs.count > 1 {
            Button("Remove Selected (\(projectVM.selectedVideoIDs.count))", role: .destructive) {
                removeSelectedVideos()
            }
        }
    }

    private func removeSelectedVideos() {
        if !projectVM.selectedVideoIDs.isEmpty {
            let idsToRemove = projectVM.selectedVideoIDs
            projectVM.videos.removeAll { idsToRemove.contains($0.id) }
            projectVM.selectedVideoIDs.removeAll()
            projectVM.selectedVideo = projectVM.videos.first
        } else if let selected = projectVM.selectedVideo {
            projectVM.removeVideo(selected)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie]

        if panel.runModal() == .OK {
            Task {
                await projectVM.addVideos(from: panel.urls)
            }
        }
    }
}

struct VideoRowView: View {
    @ObservedObject var video: VideoItem

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail
            Group {
                if let thumbnail = video.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if video.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 36)
            .background(Color.black.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(video.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if video.isLoading {
                    Text("Loading...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if let error = video.loadError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                } else {
                    Text(videoInfo)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var videoInfo: String {
        let meta = video.metadata
        var parts: [String] = []

        if meta.width > 0 && meta.height > 0 {
            parts.append("\(meta.width)x\(meta.height)")
        }

        if meta.duration > 0 {
            parts.append(meta.duration.timeDisplayString)
        }

        return parts.joined(separator: " | ")
    }
}

#Preview {
    VideoSidebarView()
        .environmentObject(ProjectViewModel())
        .frame(width: 220, height: 400)
}

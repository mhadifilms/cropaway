//
//  ProjectViewModel.swift
//  cropaway
//

import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Observation

@Observable
@MainActor
final class ProjectViewModel {
    var videos: [VideoItem] = []
    var selectedVideo: VideoItem?
    var selectedVideoIDs: Set<VideoItem.ID> = []
    var isImporting: Bool = false

    @ObservationIgnored private let metadataExtractor = VideoMetadataExtractor()

    /// Returns videos matching the current selection (for batch operations)
    var selectedVideos: [VideoItem] {
        if selectedVideoIDs.isEmpty {
            return selectedVideo.map { [$0] } ?? []
        }
        return videos.filter { selectedVideoIDs.contains($0.id) }
    }

    func addVideos(from urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }

        for url in urls {
            // Check if already added
            guard !videos.contains(where: { $0.sourceURL == url }) else { continue }

            // Verify it's a video file
            guard isVideoFile(url) else { continue }

            let video = VideoItem(sourceURL: url)
            videos.append(video)

            // Load metadata and thumbnail - AWAIT so metadata is ready before returning
            await loadVideoData(video)

            // Select first added video
            if selectedVideo == nil {
                selectedVideo = video
            }
        }
    }

    func removeVideo(_ video: VideoItem) {
        videos.removeAll { $0.id == video.id }
        if selectedVideo?.id == video.id {
            selectedVideo = videos.first
        }
    }

    func removeVideos(at offsets: IndexSet) {
        let removedIds = offsets.map { videos[$0].id }
        videos.remove(atOffsets: offsets)

        if let selected = selectedVideo, removedIds.contains(selected.id) {
            selectedVideo = videos.first
        }
    }

    func selectVideo(_ video: VideoItem) {
        selectedVideo = video
    }

    private func loadVideoData(_ video: VideoItem) async {
        do {
            try await metadataExtractor.extractMetadata(for: video)
            await video.generateThumbnail()
            video.isLoading = false
        } catch {
            video.loadError = error.localizedDescription
            video.isLoading = false
        }
    }

    private func isVideoFile(_ url: URL) -> Bool {
        let videoTypes: [UTType] = [.movie, .video, .quickTimeMovie, .mpeg4Movie, .mpeg2Video]
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return videoTypes.contains { type.conforms(to: $0) }
    }

    // Drag and drop support
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []

        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            Task {
                await self.addVideos(from: urls)
            }
        }

        return true
    }
}

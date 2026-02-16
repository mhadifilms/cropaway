//
//  ProjectViewModel.swift
//  cropaway
//

import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ProjectViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published private var selectedVideoID: VideoItem.ID?
    @Published var selectedVideoIDs: Set<VideoItem.ID> = []
    @Published var isImporting: Bool = false

    private let metadataExtractor = VideoMetadataExtractor()

    /// Selected video - computed property that validates the video still exists in the array
    /// This prevents crashes from accessing a deallocated VideoItem
    var selectedVideo: VideoItem? {
        get {
            guard let id = selectedVideoID else { return nil }
            return videos.first { $0.id == id }
        }
        set {
            selectedVideoID = newValue?.id
            objectWillChange.send()
        }
    }

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

            // Load metadata and thumbnail in background
            Task {
                await loadVideoData(video)
            }

            // Select first added video
            if selectedVideoID == nil {
                selectedVideoID = video.id
            }
        }
    }

    func removeVideo(_ video: VideoItem) {
        // Clear selection BEFORE removing to prevent accessing deallocated object
        if selectedVideoID == video.id {
            selectedVideoID = nil
        }
        selectedVideoIDs.remove(video.id)
        
        videos.removeAll { $0.id == video.id }
        
        // Select another video if we had one selected
        if selectedVideoID == nil && !videos.isEmpty {
            selectedVideoID = videos.first?.id
        }
    }

    func removeVideos(at offsets: IndexSet) {
        let removedIds = Set(offsets.map { videos[$0].id })
        
        // Clear selection BEFORE removing to prevent accessing deallocated object
        if let currentID = selectedVideoID, removedIds.contains(currentID) {
            selectedVideoID = nil
        }
        selectedVideoIDs.subtract(removedIds)
        
        videos.remove(atOffsets: offsets)
        
        // Select another video if we had one selected
        if selectedVideoID == nil && !videos.isEmpty {
            selectedVideoID = videos.first?.id
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

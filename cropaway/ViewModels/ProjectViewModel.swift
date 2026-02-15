//
//  ProjectViewModel.swift
//  cropaway
//
//  Manages the project workspace with media assets and sequences.
//

import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ProjectViewModel: ObservableObject {
    // New timeline-native model
    @Published var project: Project
    @Published var isImporting: Bool = false
    
    // Legacy support - TODO: Remove after migration
    @Published var videos: [VideoItem] = []
    @Published var selectedVideo: VideoItem?
    @Published var selectedVideoIDs: Set<VideoItem.ID> = []
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        self.project = Project(name: "Untitled Project")
        
        // Create a default sequence if none exists
        if project.sequences.isEmpty {
            _ = project.createSequence(name: "Sequence 1")
        }
    }

    // MARK: - Media Asset Management
    
    /// Add media assets from URLs (new timeline-native approach)
    func addMediaAssets(from urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        
        for url in urls {
            // Verify it's a video file
            guard isVideoFile(url) else { continue }
            
            // Create media asset
            let asset = MediaAsset(sourceURL: url)
            project.addMediaAsset(asset)
        }
    }
    
    /// Remove a media asset
    func removeMediaAsset(_ asset: MediaAsset) {
        project.removeMediaAsset(asset)
    }
    
    // MARK: - Sequence Management
    
    /// Create a new sequence
    func createSequence(name: String) -> Sequence {
        return project.createSequence(name: name)
    }
    
    /// Remove a sequence
    func removeSequence(_ sequence: Sequence) {
        project.removeSequence(sequence)
    }
    
    // MARK: - Legacy Video Support (for backward compatibility)
    
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
    
    var selectedVideos: [VideoItem] {
        if selectedVideoIDs.isEmpty {
            return selectedVideo.map { [$0] } ?? []
        }
        return videos.filter { selectedVideoIDs.contains($0.id) }
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
    
    private let metadataExtractor = VideoMetadataExtractor()

    // MARK: - Utilities
    
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
                await self.addMediaAssets(from: urls)
            }
        }

        return true
    }
}

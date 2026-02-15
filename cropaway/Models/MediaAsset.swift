//
//  MediaAsset.swift
//  Cropaway
//
//  Represents a source video file in the media pool.
//  MediaAssets are imported once and can be used multiple times in timelines.
//

import Foundation
import SwiftUI
import AVFoundation
import Combine

/// Represents a source video file in the media pool
@MainActor
final class MediaAsset: Identifiable, ObservableObject {
    // MARK: - Properties
    
    let id: UUID
    let sourceURL: URL
    @Published var fileName: String
    let dateAdded: Date
    
    // Visual metadata
    @Published var thumbnail: NSImage?
    @Published var metadata: VideoMetadata
    
    // Loading state
    @Published var isLoading: Bool = false
    @Published var loadError: String?
    
    // Cached AVAsset
    private var cachedAsset: AVURLAsset?
    
    // MARK: - Initialization
    
    init(sourceURL: URL, id: UUID = UUID()) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = sourceURL.deletingPathExtension().lastPathComponent
        self.dateAdded = Date()
        self.metadata = VideoMetadata()
        
        // Start async metadata loading
        Task {
            await loadMetadata()
        }
    }
    
    // MARK: - Asset Access
    
    /// Returns cached AVAsset or creates a new one
    func getAsset() -> AVURLAsset {
        if let cached = cachedAsset {
            return cached
        }
        let asset = AVURLAsset(url: sourceURL)
        cachedAsset = asset
        return asset
    }
    
    // MARK: - Metadata Loading
    
    private func loadMetadata() async {
        isLoading = true
        loadError = nil
        
        do {
            // Load basic metadata from AVAsset
            let asset = getAsset()
            
            // Get video track
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw NSError(domain: "MediaAsset", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
            }
            
            // Load basic properties
            let size = try await videoTrack.load(.naturalSize)
            let duration = try await asset.load(.duration)
            
            // Update metadata
            self.metadata.width = Int(size.width)
            self.metadata.height = Int(size.height)
            self.metadata.duration = duration.seconds
            
            // Generate thumbnail
            await generateThumbnail()
        } catch {
            loadError = "Failed to load video: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Generate thumbnail from first frame
    func generateThumbnail() async {
        let asset = getAsset()
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            self.thumbnail = nsImage
        } catch {
            // Thumbnail generation failed, not critical
        }
    }
}

// MARK: - Codable
// TODO: Implement Codable after VideoMetadata supports it

extension MediaAsset {
    /// Simplified serialization for storage
    struct Snapshot: Codable {
        let id: UUID
        let sourceURL: URL
        let fileName: String
        let dateAdded: Date
        // Simplified metadata - just basics
        let width: Int
        let height: Int
        let duration: Double
    }
    
    func snapshot() -> Snapshot {
        return Snapshot(
            id: id,
            sourceURL: sourceURL,
            fileName: fileName,
            dateAdded: dateAdded,
            width: metadata.width,
            height: metadata.height,
            duration: metadata.duration
        )
    }
    
    static func fromSnapshot(_ snapshot: Snapshot) -> MediaAsset {
        let asset = MediaAsset(sourceURL: snapshot.sourceURL, id: snapshot.id)
        asset.fileName = snapshot.fileName
        asset.metadata.width = snapshot.width
        asset.metadata.height = snapshot.height
        asset.metadata.duration = snapshot.duration
        return asset
    }
}

// MARK: - Hashable & Equatable

extension MediaAsset: Hashable {
    static func == (lhs: MediaAsset, rhs: MediaAsset) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

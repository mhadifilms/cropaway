//
//  ThumbnailCacheService.swift
//  cropaway
//
//  PHASE 10: Performance optimization - thumbnail caching
//

import Foundation
import AppKit
import AVFoundation

/// Manages thumbnail caching for timeline performance
actor ThumbnailCacheService {
    
    static let shared = ThumbnailCacheService()
    
    /// Cache key structure
    private struct CacheKey: Hashable {
        let videoURL: URL
        let time: Double
        let size: CGSize
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(videoURL.path)
            hasher.combine(time)
            hasher.combine(size.width)
            hasher.combine(size.height)
        }
    }
    
    /// In-memory cache
    private var cache: [CacheKey: NSImage] = [:]
    
    /// Maximum cache size (number of images)
    private let maxCacheSize = 500
    
    /// LRU tracking (most recently accessed)
    private var accessOrder: [CacheKey] = []
    
    /// Active generation tasks (prevents duplicate work)
    private var generationTasks: [CacheKey: Task<NSImage, Error>] = [:]
    
    // MARK: - Public API
    
    /// Get a thumbnail from cache or generate it
    func getThumbnail(for videoURL: URL, at time: Double, size: CGSize) async throws -> NSImage {
        let key = CacheKey(videoURL: videoURL, time: time, size: size)
        
        // Check cache first
        if let cached = cache[key] {
            updateAccessOrder(for: key)
            return cached
        }
        
        // Check if already generating
        if let existingTask = generationTasks[key] {
            return try await existingTask.value
        }
        
        // Generate new thumbnail
        let task = Task {
            try await generateThumbnail(for: videoURL, at: time, size: size)
        }
        
        generationTasks[key] = task
        
        do {
            let image = try await task.value
            cache[key] = image
            generationTasks.removeValue(forKey: key)
            updateAccessOrder(for: key)
            evictIfNeeded()
            return image
        } catch {
            generationTasks.removeValue(forKey: key)
            throw error
        }
    }
    
    /// Pre-generate thumbnails for a range of times (for timeline scrubbing)
    func prewarmCache(for videoURL: URL, times: [Double], size: CGSize) async {
        await withTaskGroup(of: Void.self) { group in
            for time in times {
                group.addTask {
                    _ = try? await self.getThumbnail(for: videoURL, at: time, size: size)
                }
            }
        }
    }
    
    /// Clear cache for a specific video
    func clearCache(for videoURL: URL) {
        let keysToRemove = cache.keys.filter { $0.videoURL == videoURL }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }
    
    /// Clear entire cache
    func clearAllCache() {
        cache.removeAll()
        accessOrder.removeAll()
        generationTasks.removeAll()
    }
    
    /// Get cache statistics
    func getCacheStats() -> (count: Int, size: Int) {
        let count = cache.count
        let estimatedSize = count * 1024 * 100 // Rough estimate: 100KB per thumbnail
        return (count, estimatedSize)
    }
    
    // MARK: - Private Helpers
    
    private func generateThumbnail(for videoURL: URL, at time: Double, size: CGSize) async throws -> NSImage {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        
        let (cgImage, _) = try await generator.image(at: cmTime)
        
        return NSImage(cgImage: cgImage, size: size)
    }
    
    private func updateAccessOrder(for key: CacheKey) {
        // Move to end (most recent)
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
    
    private func evictIfNeeded() {
        while cache.count > maxCacheSize {
            // Remove least recently used (first in accessOrder)
            guard let oldestKey = accessOrder.first else { break }
            cache.removeValue(forKey: oldestKey)
            accessOrder.removeFirst()
        }
    }
}

/// NSImage extension for size calculation
extension NSImage {
    var sizeInBytes: Int {
        guard let tiffData = self.tiffRepresentation else { return 0 }
        return tiffData.count
    }
}

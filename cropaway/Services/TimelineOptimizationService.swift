//
//  TimelineOptimizationService.swift
//  cropaway
//
//  PHASE 10: Performance optimizations for smooth 60fps timeline
//

import Foundation
import AVFoundation
import AppKit

/// Provides performance optimizations for timeline rendering
final class TimelineOptimizationService {
    
    static let shared = TimelineOptimizationService()
    
    // MARK: - Batch Operations
    
    /// Batch update multiple clips without triggering composition rebuild each time
    static func batchUpdate<T>(clips: [TimelineClip], updates: (TimelineClip) -> T) -> [T] {
        var results: [T] = []
        
        for clip in clips {
            let result = updates(clip)
            results.append(result)
        }
        
        return results
    }
    
    // MARK: - Debouncing
    
    /// Debounce helper for rapid operations
    class Debouncer {
        private var workItem: DispatchWorkItem?
        private let delay: TimeInterval
        private let queue: DispatchQueue
        
        init(delay: TimeInterval, queue: DispatchQueue = .main) {
            self.delay = delay
            self.queue = queue
        }
        
        func debounce(action: @escaping () -> Void) {
            workItem?.cancel()
            
            let newWorkItem = DispatchWorkItem(block: action)
            workItem = newWorkItem
            
            queue.asyncAfter(deadline: .now() + delay, execute: newWorkItem)
        }
        
        func cancel() {
            workItem?.cancel()
        }
    }
    
    // MARK: - Thumbnail Strip Optimization
    
    /// Pre-generate thumbnails for visible clips only
    static func prewarmVisibleClips(_ clips: [TimelineClip], visibleRange: Range<Int>) async {
        let visibleClips = clips[visibleRange.clamped(to: clips.startIndex..<clips.endIndex)]
        
        await withTaskGroup(of: Void.self) { group in
            for clip in visibleClips {
                group.addTask {
                    await clip.generateThumbnailStrip()
                }
            }
        }
    }
    
    // MARK: - Memory Management
    
    /// Clear thumbnails for clips outside visible range
    static func clearOffscreenThumbnails(_ clips: [TimelineClip], visibleRange: Range<Int>) {
        for (index, clip) in clips.enumerated() {
            if !visibleRange.contains(index) {
                Task { @MainActor in
                    clip.thumbnailStrip.removeAll()
                }
            }
        }
    }
    
    // MARK: - Composition Caching
    
    private var compositionCache: [UUID: (composition: AVMutableComposition, timestamp: Date)] = [:]
    private let cacheValidityDuration: TimeInterval = 5.0 // 5 seconds
    
    /// Get cached composition if still valid
    func getCachedComposition(for timelineID: UUID) -> AVMutableComposition? {
        guard let cached = compositionCache[timelineID] else { return nil }
        
        let age = Date().timeIntervalSince(cached.timestamp)
        if age > cacheValidityDuration {
            compositionCache.removeValue(forKey: timelineID)
            return nil
        }
        
        return cached.composition
    }
    
    /// Cache a composition
    func cacheComposition(_ composition: AVMutableComposition, for timelineID: UUID) {
        compositionCache[timelineID] = (composition, Date())
    }
    
    /// Invalidate composition cache
    func invalidateCache(for timelineID: UUID) {
        compositionCache.removeValue(forKey: timelineID)
    }
    
    /// Clear all cached compositions
    func clearAllCaches() {
        compositionCache.removeAll()
    }
}

// MARK: - Range Extensions

extension Range where Bound == Int {
    func clamped(to limits: Range<Bound>) -> Range<Bound> {
        let lowerBound = Swift.max(self.lowerBound, limits.lowerBound)
        let upperBound = Swift.min(self.upperBound, limits.upperBound)
        return lowerBound..<Swift.max(lowerBound, upperBound)
    }
}

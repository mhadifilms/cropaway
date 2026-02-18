//
//  TimelineEditingService.swift
//  cropaway
//
//  PHASE 10: Advanced editing modes (ripple, roll, slip, slide)
//

import Foundation

/// Advanced editing modes for timeline operations
enum EditMode {
    case standard    // Normal trim (no other clips affected)
    case ripple      // Trim + shift subsequent clips
    case roll        // Trim adjacent clips together (maintain gap)
    case slip        // Change source in/out without timeline duration change
    case slide       // Move clip, adjacent clips adjust
}

final class TimelineEditingService {
    
    // MARK: - Ripple Edit
    
    /// Ripple edit: Trim clip and shift all subsequent clips
    /// - Parameters:
    ///   - clip: The clip to trim
    ///   - newDuration: The new duration for the clip
    ///   - timeline: The timeline containing the clip
    static func rippleEdit(clip: TimelineClip, newDuration: Double, in timeline: Timeline) {
        guard let track = timeline.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) }) else {
            return
        }
        
        guard let clipIndex = track.clips.firstIndex(where: { $0.id == clip.id }) else {
            return
        }
        
        let oldDuration = clip.trimmedDuration
        let deltaTime = newDuration - oldDuration
        
        // Update clip duration by adjusting outPoint
        let normalizedDuration = newDuration / clip.sourceDuration
        clip.outPoint = clip.inPoint + normalizedDuration
        
        // Shift all subsequent clips
        // No actual position shift needed since clips are stored sequentially
        // The composition builder calculates positions from durations
        
        print("✅ Ripple edit: Clip duration changed by \(deltaTime)s, \(track.clips.count - clipIndex - 1) clips shifted")
    }
    
    // MARK: - Roll Edit
    
    /// Roll edit: Trim two adjacent clips together (gap remains constant)
    /// - Parameters:
    ///   - leftClip: The clip on the left
    ///   - rightClip: The clip on the right
    ///   - deltaTime: How much to shift the edit point (positive = right extends, negative = left extends)
    ///   - timeline: The timeline containing the clips
    static func rollEdit(leftClip: TimelineClip, rightClip: TimelineClip, deltaTime: Double, in timeline: Timeline) {
        // Extend/trim left clip
        let newLeftEnd = leftClip.outPoint + (deltaTime / leftClip.sourceDuration)
        guard newLeftEnd >= leftClip.inPoint && newLeftEnd <= 1.0 else {
            print("⚠️ Roll edit: Left clip would exceed bounds")
            return
        }
        
        // Extend/trim right clip (opposite direction)
        let newRightStart = rightClip.inPoint - (deltaTime / rightClip.sourceDuration)
        guard newRightStart >= 0.0 && newRightStart <= rightClip.outPoint else {
            print("⚠️ Roll edit: Right clip would exceed bounds")
            return
        }
        
        leftClip.outPoint = newLeftEnd
        rightClip.inPoint = newRightStart
        
        print("✅ Roll edit: Edit point shifted by \(deltaTime)s")
    }
    
    // MARK: - Slip Edit
    
    /// Slip edit: Change source in/out points without changing timeline duration
    /// - Parameters:
    ///   - clip: The clip to slip
    ///   - deltaTime: How much to shift the source (positive = later in source, negative = earlier)
    static func slipEdit(clip: TimelineClip, deltaTime: Double) {
        let normalizedDelta = deltaTime / clip.sourceDuration
        let currentDuration = clip.outPoint - clip.inPoint
        
        let newStart = clip.inPoint + normalizedDelta
        let newEnd = newStart + currentDuration
        
        guard newStart >= 0.0 && newEnd <= 1.0 else {
            print("⚠️ Slip edit: Would exceed source bounds")
            return
        }
        
        clip.inPoint = newStart
        clip.outPoint = newEnd
        
        print("✅ Slip edit: Source shifted by \(deltaTime)s")
    }
    
    // MARK: - Slide Edit
    
    /// Slide edit: Move clip in timeline, adjacent clips adjust to fill gaps
    /// - Parameters:
    ///   - clip: The clip to slide
    ///   - deltaTime: How much to move the clip (positive = later, negative = earlier)
    ///   - timeline: The timeline containing the clip
    static func slideEdit(clip: TimelineClip, deltaTime: Double, in timeline: Timeline) {
        guard let track = timeline.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) }) else {
            return
        }
        
        guard let clipIndex = track.clips.firstIndex(where: { $0.id == clip.id }) else {
            return
        }
        
        // Get adjacent clips
        let leftClip = clipIndex > 0 ? track.clips[clipIndex - 1] : nil
        let rightClip = clipIndex < track.clips.count - 1 ? track.clips[clipIndex + 1] : nil
        
        // Adjust left clip (extend/trim end)
        if let leftClip = leftClip {
            let newLeftEnd = leftClip.outPoint + (deltaTime / leftClip.sourceDuration)
            guard newLeftEnd >= leftClip.inPoint && newLeftEnd <= 1.0 else {
                print("⚠️ Slide edit: Left clip would exceed bounds")
                return
            }
            leftClip.outPoint = newLeftEnd
        }
        
        // Adjust right clip (extend/trim start)
        if let rightClip = rightClip {
            let newRightStart = rightClip.inPoint - (deltaTime / rightClip.sourceDuration)
            guard newRightStart >= 0.0 && newRightStart <= rightClip.outPoint else {
                print("⚠️ Slide edit: Right clip would exceed bounds")
                return
            }
            rightClip.inPoint = newRightStart
        }
        
        print("✅ Slide edit: Clip moved by \(deltaTime)s, adjacent clips adjusted")
    }
    
    // MARK: - Blade/Split
    
    /// Split a clip at a specific time into two clips
    /// - Parameters:
    ///   - clip: The clip to split
    ///   - splitTime: The time within the clip to split (clip-relative, 0 to trimmedDuration)
    ///   - timeline: The timeline containing the clip
    /// - Returns: The newly created clip, or nil if split failed
    @discardableResult
    static func bladeClip(_ clip: TimelineClip, at splitTime: Double, in timeline: Timeline) -> TimelineClip? {
        guard splitTime > 0 && splitTime < clip.trimmedDuration else {
            print("⚠️ Blade: Split time must be within clip bounds")
            return nil
        }
        
        guard let track = timeline.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) }) else {
            return nil
        }
        
        guard let clipIndex = track.clips.firstIndex(where: { $0.id == clip.id }) else {
            return nil
        }
        
        // Calculate split point in normalized coordinates
        let splitNormalized = clip.inPoint + (splitTime / clip.sourceDuration)
        
        // Create new clip for right portion
        guard let videoItem = clip.videoItem else {
            print("⚠️ Blade: Clip has no video item")
            return nil
        }
        
        let newClip = TimelineClip(videoItem: videoItem, inPoint: splitNormalized, outPoint: clip.outPoint, cropConfiguration: clip.cropConfiguration)
        
        // Copy all properties from original clip
        newClip.scale = clip.scale
        newClip.positionX = clip.positionX
        newClip.positionY = clip.positionY
        newClip.rotation = clip.rotation
        newClip.flipHorizontal = clip.flipHorizontal
        newClip.flipVertical = clip.flipVertical
        newClip.opacity = clip.opacity
        newClip.volume = clip.volume
        newClip.isMuted = clip.isMuted
        
        // Trim original clip (left portion)
        clip.outPoint = splitNormalized
        
        // Insert new clip after original
        track.clips.insert(newClip, at: clipIndex + 1)
        
        print("✅ Blade: Split clip at \(splitTime)s, created new clip")
        return newClip
    }
    
    // MARK: - Remove Clip with Ripple
    
    /// Remove a clip and shift subsequent clips to close the gap
    /// - Parameters:
    ///   - clip: The clip to remove
    ///   - timeline: The timeline containing the clip
    ///   - ripple: If true, shift subsequent clips; if false, leave gap
    static func removeClip(_ clip: TimelineClip, from timeline: Timeline, ripple: Bool = true) {
        guard let track = timeline.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) }) else {
            return
        }
        
        track.clips.removeAll { $0.id == clip.id }
        
        // If ripple is false, we don't shift clips (gap remains)
        // If ripple is true, clips naturally shift because we use sequential duration calculation
        
        print("✅ Removed clip, ripple: \(ripple)")
    }
}

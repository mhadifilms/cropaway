//
//  TransitionCompositionBuilder.swift
//  cropaway
//

import Foundation
import AVFoundation

/// Service for building AVVideoComposition with transition support
/// Enables real-time rendering of transitions during timeline playback
@MainActor
final class TransitionCompositionBuilder {
    
    /// Layout information for a single clip in the timeline
    struct ClipLayout {
        let clipIndex: Int
        let startTime: CMTime
        let duration: CMTime
        let trackID: CMPersistentTrackID
    }
    
    /// Layout information for a transition between clips
    struct TransitionLayout {
        let transitionIndex: Int
        let type: TransitionType
        let timeRange: CMTimeRange
        let fromTrackID: CMPersistentTrackID
        let toTrackID: CMPersistentTrackID
    }
    
    /// Complete timeline layout with clips and transitions
    struct TimelineLayout {
        let clips: [ClipLayout]
        let transitions: [TransitionLayout]
        
        var hasTransitions: Bool {
            !transitions.isEmpty
        }
    }
    
    /// Build an AVVideoComposition with transition support
    /// - Parameters:
    ///   - composition: The base AVComposition (from TimelineCompositionBuilder)
    ///   - timeline: The timeline with clips and transitions
    /// - Returns: Video composition with custom rendering for transitions, or nil if no transitions
    static func buildVideoComposition(
        for composition: AVComposition,
        timeline: Timeline
    ) -> AVVideoComposition? {
        
        // Calculate timeline layout with transition ranges
        let layout = calculateTimelineLayout(composition: composition, timeline: timeline)
        
        // If no transitions that require custom rendering, return default
        let hasCustomTransitions = layout.transitions.contains { $0.type != .cut }
        guard hasCustomTransitions else {
            return AVVideoComposition(propertiesOf: composition)
        }
        
        // Get video track from composition
        guard let videoTrack = composition.tracks(withMediaType: .video).first else {
            return AVVideoComposition(propertiesOf: composition)
        }
        
        // Create mutable video composition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = videoTrack.naturalSize
        
        // Set custom compositor for transitions
        videoComposition.customVideoCompositorClass = TransitionVideoCompositor.self
        
        // Build instructions for each segment
        var instructions: [AVVideoCompositionInstructionProtocol] = []
        
        for (index, clipLayout) in layout.clips.enumerated() {
            // Check if there's a transition at the start of this clip
            if let transition = layout.transitions.first(where: { $0.transitionIndex == index - 1 }) {
                // Add transition instruction
                let transitionInstruction = TransitionCompositionInstruction(
                    timeRange: transition.timeRange,
                    fromTrackID: transition.fromTrackID,
                    toTrackID: transition.toTrackID,
                    transitionType: transition.type
                )
                instructions.append(transitionInstruction)
            }
            
            // Calculate clip's post-transition range
            var clipStartTime = clipLayout.startTime
            var clipDuration = clipLayout.duration
            
            // If there was a transition at the start, adjust clip start time
            if let transition = layout.transitions.first(where: { $0.transitionIndex == index - 1 }) {
                let transitionEnd = CMTimeAdd(transition.timeRange.start, transition.timeRange.duration)
                clipStartTime = transitionEnd
                clipDuration = CMTimeSubtract(CMTimeAdd(clipLayout.startTime, clipLayout.duration), transitionEnd)
            }
            
            // Only add clip instruction if there's remaining duration after transition
            if clipDuration.seconds > 0.001 {
                let clipInstruction = AVMutableVideoCompositionInstruction()
                clipInstruction.timeRange = CMTimeRange(start: clipStartTime, duration: clipDuration)
                
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                clipInstruction.layerInstructions = [layerInstruction]
                
                instructions.append(clipInstruction)
            }
        }
        
        videoComposition.instructions = instructions
        
        return videoComposition
    }
    
    /// Calculate timeline layout with clip positions and transition ranges
    private static func calculateTimelineLayout(
        composition: AVComposition,
        timeline: Timeline
    ) -> TimelineLayout {
        
        guard let videoTrack = composition.tracks(withMediaType: .video).first else {
            return TimelineLayout(clips: [], transitions: [])
        }
        
        var clipLayouts: [ClipLayout] = []
        var transitionLayouts: [TransitionLayout] = []
        
        var currentTime = CMTime.zero
        
        // Build clip layouts
        for (index, clip) in timeline.clips.enumerated() {
            let duration = CMTime(seconds: clip.trimmedDuration, preferredTimescale: 600)
            
            let clipLayout = ClipLayout(
                clipIndex: index,
                startTime: currentTime,
                duration: duration,
                trackID: videoTrack.trackID
            )
            clipLayouts.append(clipLayout)
            
            // Check for transition after this clip
            if let transition = timeline.transition(afterClipIndex: index),
               transition.effectiveDuration > 0,
               transition.type != .cut {
                
                // Get next clip's track ID (same track in this simple implementation)
                let nextClipLayout = ClipLayout(
                    clipIndex: index + 1,
                    startTime: CMTimeAdd(currentTime, duration),
                    duration: CMTime(seconds: timeline.clips[index + 1].trimmedDuration, preferredTimescale: 600),
                    trackID: videoTrack.trackID
                )
                
                // Transition starts at end of current clip
                let transitionStart = CMTimeAdd(currentTime, duration)
                let transitionDuration = CMTime(seconds: transition.effectiveDuration, preferredTimescale: 600)
                
                let transitionLayout = TransitionLayout(
                    transitionIndex: index,
                    type: transition.type,
                    timeRange: CMTimeRange(start: transitionStart, duration: transitionDuration),
                    fromTrackID: clipLayout.trackID,
                    toTrackID: nextClipLayout.trackID
                )
                transitionLayouts.append(transitionLayout)
            }
            
            currentTime = CMTimeAdd(currentTime, duration)
        }
        
        return TimelineLayout(clips: clipLayouts, transitions: transitionLayouts)
    }
}

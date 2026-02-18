//
//  TimelineCompositionBuilder.swift
//  cropaway
//

import Foundation
import AVFoundation

/// Service for building AVComposition from Timeline clips
/// This enables seamless playback of multiple trimmed clips as a single video
@MainActor
final class TimelineCompositionBuilder {

    /// Build an AVComposition from a Timeline (synchronous wrapper)
    /// - Parameter timeline: The timeline containing clips to compose
    /// - Returns: A composition that can be played seamlessly, or nil if timeline is empty
    static func buildComposition(from timeline: Timeline) -> AVMutableComposition? {
        // Block on async implementation
        let semaphore = DispatchSemaphore(value: 0)
        var result: AVMutableComposition?
        
        Task {
            result = await buildCompositionAsync(from: timeline)
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
    
    /// Build an AVComposition from a Timeline (async implementation)
    private static func buildCompositionAsync(from timeline: Timeline) async -> AVMutableComposition? {
        // PHASE 4: Support multi-track timelines
        guard !timeline.allClips.isEmpty else { return nil }

        let composition = AVMutableComposition()

        // PHASE 4: Create tracks for each timeline track (multi-track support)
        var compositionVideoTracks: [(track: AVMutableCompositionTrack, sourceTrack: Track)] = []
        
        // Create composition video tracks for each timeline video track
        for timelineTrack in timeline.videoTracks {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }
            compositionVideoTracks.append((compositionTrack, timelineTrack))
        }
        
        // Create single audio track (will mix all audio sources)
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }

        // Process each video track
        for (compositionTrack, timelineTrack) in compositionVideoTracks {
            var currentTime = CMTime.zero
            
            // Add each clip in the track
            for clip in timelineTrack.clips {
            guard let video = clip.videoItem else { continue }

            let asset = video.getAsset()

            // Get video track from source
            guard let sourceVideoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                continue
            }

            // CRITICAL FIX: Use asset's native timescale, not hardcoded 600
            guard let assetDuration = try? await asset.load(.duration) else {
                continue
            }
            let assetTimescale = assetDuration.timescale

            // Calculate start time using asset's native timescale
            let startSeconds = clip.sourceStartTime
            let startTime = CMTime(
                value: CMTimeValue(startSeconds * Double(assetTimescale)),
                timescale: assetTimescale
            )

            // Calculate duration using asset's native timescale
            let durationSeconds = clip.trimmedDuration
            let duration = CMTime(
                value: CMTimeValue(durationSeconds * Double(assetTimescale)),
                timescale: assetTimescale
            )

            // Clamp to asset bounds to prevent over-read
            let clampedStart = CMTimeMaximum(startTime, CMTime.zero)
            let maxDuration = CMTimeSubtract(assetDuration, clampedStart)
            let clampedDuration = CMTimeMinimum(duration, maxDuration)

            let sourceRange = CMTimeRange(start: clampedStart, duration: clampedDuration)

            do {
                // Insert video track into this composition track
                try compositionTrack.insertTimeRange(
                    sourceRange,
                    of: sourceVideoTrack,
                    at: currentTime
                )

                // Insert audio track if present (all tracks share the same audio track)
                if let sourceAudioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                    try audioTrack.insertTimeRange(
                        sourceRange,
                        of: sourceAudioTrack,
                        at: currentTime
                    )
                }

                // Advance current time for this track
                currentTime = CMTimeAdd(currentTime, clampedDuration)

            } catch {
                print("⚠️ Failed to insert clip \(clip.id) into composition: \(error)")
                continue
            }
            }
            
            // Apply video track's preferred transform to maintain orientation
            if let firstClip = timelineTrack.clips.first,
               let firstAsset = firstClip.videoItem?.getAsset() {
                if let firstVideoTrack = try? await firstAsset.loadTracks(withMediaType: .video).first,
                   let transform = try? await firstVideoTrack.load(.preferredTransform) {
                    compositionTrack.preferredTransform = transform
                }
            }
        }

        return composition
    }
    
    // PHASE 9: Build audio mix with per-clip volume
    /// - Parameter timeline: The timeline containing clips with volume settings
    /// - Parameter composition: The composition to apply audio mix to
    /// - Returns: AVAudioMix with volume parameters applied
    static func buildAudioMix(for timeline: Timeline, composition: AVComposition) -> AVAudioMix? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: AVAudioMix?
        
        Task {
            result = await buildAudioMixAsync(for: timeline, composition: composition)
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
    
    /// Build an AVAudioMix with per-clip volume control (async implementation)
    private static func buildAudioMixAsync(for timeline: Timeline, composition: AVComposition) async -> AVAudioMix? {
        let audioMix = AVMutableAudioMix()
        var inputParameters: [AVMutableAudioMixInputParameters] = []
        
        // Get all audio tracks from composition
        guard let audioTracks = try? await composition.loadTracks(withMediaType: .audio) else {
            return nil
        }
        guard !audioTracks.isEmpty else { return nil }
        
        // For each audio track in the composition
        for (_, compositionAudioTrack) in audioTracks.enumerated() {
            let params = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
            
            // Apply volume ramps for each clip
            var currentTime = CMTime.zero
            
            for clip in timeline.allClips {
                guard let video = clip.videoItem else { continue }
                let asset = video.getAsset()
                
                // Check if this clip has audio
                let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
                guard !audioTracks.isEmpty else { continue }
                
                // Calculate clip duration
                guard let assetDuration = try? await asset.load(.duration) else { continue }
                let assetTimescale = assetDuration.timescale
                let durationSeconds = clip.trimmedDuration
                let clipDuration = CMTime(
                    value: CMTimeValue(durationSeconds * Double(assetTimescale)),
                    timescale: assetTimescale
                )
                
                // Apply volume based on clip settings
                let volume = clip.isMuted ? 0.0 : clip.volume
                
                // Set volume for this time range
                params.setVolume(volume, at: currentTime)
                
                // Advance current time
                currentTime = CMTimeAdd(currentTime, clipDuration)
            }
            
            inputParameters.append(params)
        }
        
        audioMix.inputParameters = inputParameters
        return audioMix
    }

    /// Build a composition with transitions applied
    /// - Parameters:
    ///   - timeline: The timeline with clips and transitions
    ///   - applyTransitions: Whether to apply cross-dissolve transitions
    /// - Returns: A composition with transitions, or nil if timeline is empty
    static func buildCompositionWithTransitions(from timeline: Timeline, applyTransitions: Bool = true) -> AVMutableComposition? {
        // For now, just build basic composition
        // Transition support with AVVideoComposition will be added in phase 2
        return buildComposition(from: timeline)
    }

    /// Build an AVVideoComposition that applies custom rendering (for transitions, effects)
    /// - Parameter composition: The base composition
    /// - Returns: Video composition with custom instructions
    static func buildVideoComposition(for composition: AVComposition) -> AVVideoComposition? {
        // This will be used for:
        // 1. Cross-dissolve transitions
        // 2. Optical flow transitions
        // 3. Custom effects
        // For now, return default
        return AVVideoComposition(propertiesOf: composition)
    }
    
}

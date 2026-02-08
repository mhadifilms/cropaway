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

    /// Build an AVComposition from a Timeline
    /// - Parameter timeline: The timeline containing clips to compose
    /// - Returns: A composition that can be played seamlessly, or nil if timeline is empty
    static func buildComposition(from timeline: Timeline) -> AVMutableComposition? {
        guard !timeline.clips.isEmpty else { return nil }

        let composition = AVMutableComposition()

        // Create video and audio tracks
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }

        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }

        var currentTime = CMTime.zero

        // Add each clip to the composition
        for clip in timeline.clips {
            guard let video = clip.videoItem else { continue }

            let asset = video.getAsset()

            // Get video track from source
            guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
                continue
            }

            // CRITICAL FIX: Use asset's native timescale, not hardcoded 600
            let assetDuration = asset.duration
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
                // Insert video track
                try videoTrack.insertTimeRange(
                    sourceRange,
                    of: sourceVideoTrack,
                    at: currentTime
                )

                // Insert audio track if present
                if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first {
                    try audioTrack.insertTimeRange(
                        sourceRange,
                        of: sourceAudioTrack,
                        at: currentTime
                    )
                }

                // Advance current time
                currentTime = CMTimeAdd(currentTime, clampedDuration)

            } catch {
                print("⚠️ Failed to insert clip \(clip.id) into composition: \(error)")
                continue
            }
        }

        // Apply video track's preferred transform to maintain orientation
        if let firstClip = timeline.clips.first,
           let firstAsset = firstClip.videoItem?.getAsset(),
           let firstVideoTrack = firstAsset.tracks(withMediaType: .video).first {
            videoTrack.preferredTransform = firstVideoTrack.preferredTransform
        }

        return composition
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

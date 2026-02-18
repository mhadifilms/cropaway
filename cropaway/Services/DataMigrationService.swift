//
//  DataMigrationService.swift
//  cropaway
//
//  Created by Claude Code
//

import Foundation

/// Service responsible for migrating timeline data from old formats to new multi-track format
@MainActor
final class DataMigrationService {
    
    // MARK: - Timeline Migration
    
    /// Migrate a timeline from single-track (clips array) to multi-track format
    /// - Parameter timeline: The timeline to migrate
    /// - Returns: The migrated timeline (modifies in place and returns for convenience)
    @discardableResult
    static func migrateTimeline(_ timeline: Timeline) -> Timeline {
        // Check if already migrated (has tracks)
        guard timeline.tracks.isEmpty else {
            return timeline
        }
        
        // Check if there are clips to migrate
        guard !timeline.clips.isEmpty else {
            return timeline
        }
        
        print("📦 Migrating timeline '\(timeline.name)' from single-track to multi-track format...")
        
        // Create a single video track with all existing clips
        let videoTrack = Track(
            name: "Video 1",
            clips: timeline.clips,
            mediaType: .video,
            verticalOrder: 0
        )
        
        // Migrate per-video crops to per-clip crops
        migrateClipCropConfigurations(in: videoTrack)
        
        // Add track to timeline
        timeline.tracks = [videoTrack]
        
        print("✅ Migration complete: Created 1 video track with \(videoTrack.clips.count) clips")
        
        return timeline
    }
    
    /// Migrate multiple timelines at once
    /// - Parameter timelines: Array of timelines to migrate
    /// - Returns: Array of migrated timelines
    static func migrateTimelines(_ timelines: [Timeline]) -> [Timeline] {
        timelines.map { migrateTimeline($0) }
    }
    
    // MARK: - Clip Crop Migration
    
    /// Migrate clip crop configurations from per-video to per-clip
    /// - Parameter track: The track containing clips to migrate
    private static func migrateClipCropConfigurations(in track: Track) {
        for clip in track.clips {
            // Skip if clip already has its own crop configuration
            if clip.cropConfiguration != nil {
                continue
            }
            
            // Clone crop configuration from source video
            if let videoItem = clip.videoItem {
                let clonedConfig = CropConfiguration(from: videoItem.cropConfiguration)
                
                // Migrate keyframe timestamps from absolute to clip-relative
                migrateKeyframeTimestamps(
                    in: clonedConfig,
                    clipStartTime: clip.sourceStartTime,
                    clipDuration: clip.trimmedDuration
                )
                
                // Assign cloned configuration to clip
                clip.cropConfiguration = clonedConfig
            }
        }
    }
    
    /// Migrate keyframe timestamps from absolute video time to clip-relative time
    /// - Parameters:
    ///   - cropConfig: The crop configuration containing keyframes
    ///   - clipStartTime: The start time of the clip in the source video (seconds)
    ///   - clipDuration: The duration of the clip (seconds)
    private static func migrateKeyframeTimestamps(
        in cropConfig: CropConfiguration,
        clipStartTime: Double,
        clipDuration: Double
    ) {
        guard cropConfig.keyframesEnabled, !cropConfig.keyframes.isEmpty else {
            return
        }
        
        var migratedKeyframes: [Keyframe] = []
        
        for keyframe in cropConfig.keyframes {
            // Convert absolute timestamp to clip-relative
            let absoluteTime = keyframe.timestamp
            let clipRelativeTime = absoluteTime - clipStartTime
            
            // Only include keyframes that fall within the clip's range
            if clipRelativeTime >= 0 && clipRelativeTime <= clipDuration {
                let newKeyframe = keyframe.copy()
                newKeyframe.timestamp = clipRelativeTime
                migratedKeyframes.append(newKeyframe)
            }
        }
        
        cropConfig.keyframes = migratedKeyframes
        
        print("  🔄 Migrated \(migratedKeyframes.count) keyframes to clip-relative timestamps")
    }
    
    // MARK: - Validation
    
    /// Validate that a timeline has been properly migrated
    /// - Parameter timeline: The timeline to validate
    /// - Returns: True if timeline is in valid multi-track format
    static func validateMigration(_ timeline: Timeline) -> Bool {
        // Timeline should have tracks
        guard !timeline.tracks.isEmpty else {
            print("⚠️ Validation failed: Timeline has no tracks")
            return false
        }
        
        // All clips should have their own crop configurations
        for track in timeline.tracks {
            for clip in track.clips {
                guard clip.hasOwnCropConfiguration else {
                    print("⚠️ Validation failed: Clip \(clip.id) missing crop configuration")
                    return false
                }
            }
        }
        
        print("✅ Timeline '\(timeline.name)' validation passed")
        return true
    }
}

// MARK: - Timeline Extensions

extension Timeline {
    /// Whether this timeline needs migration
    var needsMigration: Bool {
        tracks.isEmpty && !clips.isEmpty
    }
    
    /// Migrate this timeline if needed
    @discardableResult
    func migrateIfNeeded() -> Bool {
        guard needsMigration else {
            return false
        }
        DataMigrationService.migrateTimeline(self)
        return true
    }
}

// MARK: - TimelineClip Extensions

extension TimelineClip {
    /// Whether this clip has its own crop configuration (not shared from video)
    var hasOwnCropConfiguration: Bool {
        // This will be properly implemented once we add cropConfiguration to TimelineClip
        // For now, we'll check if it exists
        return cropConfiguration != nil
    }
}

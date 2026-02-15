//
//  TimelineViewModel.swift
//  Cropaway
//
//  Manages timeline editing operations: clip selection, movement, trimming, etc.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class TimelineViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var sequence: Sequence?
    @Published var selectedClips: Set<TimelineClip.ID> = []
    @Published var zoomLevel: Double = 100.0  // Pixels per second
    @Published var playheadPosition: Double = 0  // Synced with player
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var selectedClipObjects: [TimelineClip] {
        guard let sequence = sequence else { return [] }
        return sequence.clips.filter { selectedClips.contains($0.id) }
    }
    
    var hasSelection: Bool {
        !selectedClips.isEmpty
    }
    
    // MARK: - Binding
    
    func bind(to sequence: Sequence) {
        self.sequence = sequence
        selectedClips.removeAll()
    }
    
    func unbind() {
        sequence = nil
        selectedClips.removeAll()
    }
    
    // MARK: - Selection
    
    func selectClip(_ clip: TimelineClip, extending: Bool = false) {
        if extending {
            selectedClips.insert(clip.id)
        } else {
            selectedClips = [clip.id]
        }
    }
    
    func deselectClip(_ clip: TimelineClip) {
        selectedClips.remove(clip.id)
    }
    
    func deselectAll() {
        selectedClips.removeAll()
    }
    
    func selectAll() {
        guard let sequence = sequence else { return }
        selectedClips = Set(sequence.clips.map { $0.id })
    }
    
    func isSelected(_ clip: TimelineClip) -> Bool {
        selectedClips.contains(clip.id)
    }
    
    // MARK: - Clip Operations
    
    /// Add a clip to the timeline at a specific time
    func addClip(mediaAsset: MediaAsset, at time: Double, sourceInPoint: Double = 0, sourceOutPoint: Double? = nil) {
        guard let sequence = sequence else { return }
        
        let outPoint = sourceOutPoint ?? mediaAsset.metadata.duration
        
        let clip = TimelineClip(
            mediaAsset: mediaAsset,
            startTime: time,
            sourceInPoint: sourceInPoint,
            sourceOutPoint: outPoint
        )
        
        sequence.addClip(clip)
        selectedClips = [clip.id]
    }
    
    /// Move a clip to a new start time
    func moveClip(_ clip: TimelineClip, to newStartTime: Double) {
        guard let sequence = sequence else { return }
        sequence.moveClip(clip, toTime: newStartTime)
    }
    
    /// Move selected clips by a delta
    func moveSelectedClips(by delta: Double) {
        guard let sequence = sequence else { return }
        
        for clip in selectedClipObjects {
            let newTime = max(0, clip.startTime + delta)
            sequence.moveClip(clip, toTime: newTime)
        }
    }
    
    /// Delete selected clips
    func deleteSelectedClips() {
        guard let sequence = sequence else { return }
        sequence.removeClips(withIds: selectedClips)
        selectedClips.removeAll()
    }
    
    /// Ripple delete: remove clips and shift subsequent clips left
    func rippleDeleteSelectedClips() {
        guard let sequence = sequence else { return }
        
        // Sort selected clips by start time
        let clipsToDelete = selectedClipObjects.sorted { $0.startTime < $1.startTime }
        
        for clip in clipsToDelete {
            sequence.rippleDeleteClip(clip)
        }
        
        selectedClips.removeAll()
    }
    
    /// Split clip at a specific time
    func splitClip(_ clip: TimelineClip, at sequenceTime: Double) -> (TimelineClip, TimelineClip)? {
        guard let sequence = sequence else { return nil }
        guard clip.contains(sequenceTime: sequenceTime) else { return nil }
        
        // Calculate split point in source time
        let sourceTime = clip.sourceTime(fromSequenceTime: sequenceTime)
        
        // Create first clip (original up to split point)
        let firstClip = TimelineClip(
            mediaAsset: clip.mediaAsset,
            startTime: clip.startTime,
            sourceInPoint: clip.sourceInPoint,
            sourceOutPoint: sourceTime
        )
        firstClip.cropConfiguration = clip.cropConfiguration.copy()
        firstClip.name = clip.name + " (1)"
        
        // Create second clip (from split point to end)
        let secondClip = TimelineClip(
            mediaAsset: clip.mediaAsset,
            startTime: sequenceTime,
            sourceInPoint: sourceTime,
            sourceOutPoint: clip.sourceOutPoint
        )
        secondClip.cropConfiguration = clip.cropConfiguration.copy()
        secondClip.name = clip.name + " (2)"
        
        // For keyframes, need to adjust timestamps
        // First clip: keep keyframes before split
        // Second clip: keep keyframes after split and adjust timestamps
        if clip.cropConfiguration.hasKeyframes {
            let splitLocalTime = clip.clipLocalTime(fromSequenceTime: sequenceTime)
            
            firstClip.cropConfiguration.keyframes = clip.cropConfiguration.keyframes
                .filter { $0.timestamp <= splitLocalTime }
            
            secondClip.cropConfiguration.keyframes = clip.cropConfiguration.keyframes
                .filter { $0.timestamp > splitLocalTime }
                .map { keyframe in
                    let newKeyframe = keyframe.copy()
                    newKeyframe.timestamp -= splitLocalTime
                    return newKeyframe
                }
        }
        
        // Remove original clip
        sequence.removeClip(clip)
        
        // Add new clips
        sequence.addClip(firstClip)
        sequence.addClip(secondClip)
        
        // Select both new clips
        selectedClips = [firstClip.id, secondClip.id]
        
        return (firstClip, secondClip)
    }
    
    // MARK: - Trimming Operations
    
    /// Trim the start of a clip
    func trimClipStart(_ clip: TimelineClip, by delta: Double) {
        // Adjust source in point
        clip.trimStart(by: delta)
        
        // Also adjust start time on timeline
        clip.startTime += delta
    }
    
    /// Trim the end of a clip
    func trimClipEnd(_ clip: TimelineClip, by delta: Double) {
        clip.trimEnd(by: delta)
    }
    
    /// Slip edit: adjust source in/out without changing timeline position or duration
    func slipClip(_ clip: TimelineClip, by delta: Double) {
        clip.slip(by: delta)
    }
    
    // MARK: - Timeline Navigation
    
    /// Snap time to nearest frame
    func snapToFrame(_ time: Double) -> Double {
        guard let sequence = sequence else { return time }
        let frameDuration = 1.0 / sequence.frameRate
        return round(time / frameDuration) * frameDuration
    }
    
    /// Get clip at a specific timeline position
    func getClipAt(time: Double) -> TimelineClip? {
        return sequence?.getClipAt(sequenceTime: time)
    }
    
    // MARK: - Zoom
    
    func zoomIn() {
        zoomLevel = min(zoomLevel * 1.5, 500.0)  // Max 500 pixels per second
    }
    
    func zoomOut() {
        zoomLevel = max(zoomLevel / 1.5, 10.0)  // Min 10 pixels per second
    }
    
    func resetZoom() {
        zoomLevel = 100.0
    }
    
    // MARK: - Clipboard Operations
    
    private var clipboard: [TimelineClip] = []
    
    func copySelectedClips() {
        clipboard = selectedClipObjects.map { clip in
            let copy = TimelineClip(
                mediaAsset: clip.mediaAsset,
                startTime: clip.startTime,
                sourceInPoint: clip.sourceInPoint,
                sourceOutPoint: clip.sourceOutPoint
            )
            copy.cropConfiguration = clip.cropConfiguration.copy()
            copy.name = clip.name
            return copy
        }
    }
    
    func pasteClips(at time: Double) {
        guard let sequence = sequence else { return }
        guard !clipboard.isEmpty else { return }
        
        // Calculate offset from first clip in clipboard
        let firstClipStart = clipboard.map { $0.startTime }.min() ?? 0
        let offset = time - firstClipStart
        
        var newClipIds: Set<TimelineClip.ID> = []
        
        for clipToCopy in clipboard {
            let newClip = TimelineClip(
                mediaAsset: clipToCopy.mediaAsset,
                startTime: clipToCopy.startTime + offset,
                sourceInPoint: clipToCopy.sourceInPoint,
                sourceOutPoint: clipToCopy.sourceOutPoint
            )
            newClip.cropConfiguration = clipToCopy.cropConfiguration.copy()
            newClip.name = clipToCopy.name
            
            sequence.addClip(newClip)
            newClipIds.insert(newClip.id)
        }
        
        selectedClips = newClipIds
    }
    
    func duplicateSelectedClips() {
        guard !selectedClipObjects.isEmpty else { return }
        
        // Find the rightmost selected clip
        let maxEndTime = selectedClipObjects.map { $0.endTime }.max() ?? 0
        
        copySelectedClips()
        pasteClips(at: maxEndTime)
    }
    
    // MARK: - Timeline Navigation
    
    func selectNextClip() {
        guard let sequence = sequence else { return }
        
        if let currentClip = selectedClipObjects.first {
            // Find next clip
            let sortedClips = sequence.clips.sorted { $0.startTime < $1.startTime }
            if let currentIndex = sortedClips.firstIndex(where: { $0.id == currentClip.id }),
               currentIndex < sortedClips.count - 1 {
                let nextClip = sortedClips[currentIndex + 1]
                selectClip(nextClip, extending: false)
            }
        } else if let firstClip = sequence.clips.sorted(by: { $0.startTime < $1.startTime }).first {
            // No selection, select first clip
            selectClip(firstClip, extending: false)
        }
    }
    
    func selectPreviousClip() {
        guard let sequence = sequence else { return }
        
        if let currentClip = selectedClipObjects.first {
            // Find previous clip
            let sortedClips = sequence.clips.sorted { $0.startTime < $1.startTime }
            if let currentIndex = sortedClips.firstIndex(where: { $0.id == currentClip.id }),
               currentIndex > 0 {
                let prevClip = sortedClips[currentIndex - 1]
                selectClip(prevClip, extending: false)
            }
        } else if let lastClip = sequence.clips.sorted(by: { $0.startTime < $1.startTime }).last {
            // No selection, select last clip
            selectClip(lastClip, extending: false)
        }
    }
    
    // MARK: - In/Out Points
    
    func setInPoint(at time: Double) {
        sequence?.inPoint = time
    }
    
    func setOutPoint(at time: Double) {
        sequence?.outPoint = time
    }
    
    func clearInOutPoints() {
        sequence?.inPoint = nil
        sequence?.outPoint = nil
    }
}

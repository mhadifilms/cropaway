//
//  KeyframeViewModel.swift
//  cropaway
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class KeyframeViewModel: ObservableObject {
    @Published var keyframes: [Keyframe] = []
    @Published var keyframesEnabled: Bool = true
    @Published var selectedKeyframeIDs: Set<UUID> = []
    @Published var updateTrigger: Bool = false  // Toggle to force view refresh

    private var currentVideo: VideoItem?
    private var cropEditor: CropEditorViewModel?
    private var cancellables = Set<AnyCancellable>()

    // Convenience for single selection (primary selected keyframe)
    var selectedKeyframe: Keyframe? {
        get {
            guard let firstID = selectedKeyframeIDs.first else { return nil }
            return keyframes.first { $0.id == firstID }
        }
        set {
            if let kf = newValue {
                selectedKeyframeIDs = [kf.id]
            } else {
                selectedKeyframeIDs.removeAll()
            }
        }
    }

    var selectedKeyframes: [Keyframe] {
        keyframes.filter { selectedKeyframeIDs.contains($0.id) }
    }
    
    /// Snaps a timestamp to the nearest frame boundary based on the video's frame rate
    private func snapToFrame(_ timestamp: Double) -> Double {
        guard let frameRate = currentVideo?.metadata.frameRate, frameRate > 0 else {
            return timestamp
        }
        let frameDuration = 1.0 / frameRate
        let frameIndex = (timestamp / frameDuration).rounded()
        return frameIndex * frameDuration
    }

    func bind(to video: VideoItem, cropEditor: CropEditorViewModel) {
        cancellables.removeAll()
        currentVideo = video
        self.cropEditor = cropEditor

        let config = video.cropConfiguration

        // Sync from config
        keyframes = config.keyframes
        keyframesEnabled = config.keyframesEnabled
        selectedKeyframeIDs.removeAll()

        // Sync changes back
        $keyframesEnabled
            .dropFirst()
            .sink { config.keyframesEnabled = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Selection

    func selectKeyframe(_ keyframe: Keyframe, extending: Bool = false) {
        if extending {
            // Shift-click: toggle in selection
            if selectedKeyframeIDs.contains(keyframe.id) {
                selectedKeyframeIDs.remove(keyframe.id)
            } else {
                selectedKeyframeIDs.insert(keyframe.id)
            }
        } else {
            // Regular click: exclusive selection
            selectedKeyframeIDs = [keyframe.id]
            // Apply the selected keyframe's crop state to the editor
            applyKeyframeToEditor(keyframe)
        }
    }

    func selectKeyframe(at timestamp: Double) {
        if let kf = keyframes.first(where: { abs($0.timestamp - timestamp) < 0.1 }) {
            selectedKeyframeIDs = [kf.id]
            // Apply the selected keyframe's crop state to the editor
            applyKeyframeToEditor(kf)
        }
    }
    
    /// Applies a keyframe's crop state directly to the crop editor
    private func applyKeyframeToEditor(_ keyframe: Keyframe) {
        guard let cropEditor = cropEditor else { return }
        
        // Don't apply if it's an absent keyframe (no crop)
        guard !keyframe.isAbsent else { return }
        
        cropEditor.cropRect = keyframe.cropRect
        cropEditor.edgeInsets = keyframe.edgeInsets
        cropEditor.circleCenter = keyframe.circleCenter
        cropEditor.circleRadius = keyframe.circleRadius
        
        // Apply freehand path data
        if let pathData = keyframe.freehandPathData {
            cropEditor.freehandPathData = pathData
        }
        
        // Apply AI mask data
        if let aiMaskData = keyframe.aiMaskData {
            cropEditor.aiMaskData = aiMaskData
        }
        if let aiBoundingBox = keyframe.aiBoundingBox {
            cropEditor.aiBoundingBox = aiBoundingBox
            // Sync cropRect with aiBoundingBox in AI mode
            if cropEditor.mode == .ai && aiBoundingBox.width > 0 {
                cropEditor.cropRect = aiBoundingBox
            }
        }
    }

    func deselectAll() {
        selectedKeyframeIDs.removeAll()
    }

    func selectAll() {
        selectedKeyframeIDs = Set(keyframes.map { $0.id })
    }

    func isSelected(_ keyframe: Keyframe) -> Bool {
        selectedKeyframeIDs.contains(keyframe.id)
    }

    // MARK: - Add/Remove

    func addKeyframe(at timestamp: Double, isAbsent: Bool = false) {
        guard let cropEditor = cropEditor else { return }

        // Snap timestamp to nearest frame boundary
        let snappedTimestamp = snapToFrame(timestamp)
        
        let keyframe = Keyframe(
            timestamp: snappedTimestamp,
            cropRect: cropEditor.cropRect,
            edgeInsets: cropEditor.edgeInsets,
            circleCenter: cropEditor.circleCenter,
            circleRadius: cropEditor.circleRadius,
            isAbsent: isAbsent
        )

        // Include freehand path data (only for non-absent keyframes)
        if !isAbsent {
            keyframe.freehandPathData = cropEditor.freehandPathData

            // Include AI mask data
            if cropEditor.mode == .ai || cropEditor.aiMaskData != nil {
                keyframe.aiMaskData = cropEditor.aiMaskData
                keyframe.aiPromptPoints = cropEditor.aiPromptPoints.isEmpty ? nil : cropEditor.aiPromptPoints
                keyframe.aiBoundingBox = cropEditor.aiBoundingBox.width > 0 ? cropEditor.aiBoundingBox : nil
            }
        }

        // Insert in sorted order
        if let insertIndex = keyframes.firstIndex(where: { $0.timestamp > snappedTimestamp }) {
            keyframes.insert(keyframe, at: insertIndex)
        } else {
            keyframes.append(keyframe)
        }

        currentVideo?.cropConfiguration.keyframes = keyframes
        selectedKeyframeIDs = [keyframe.id]
    }

    func removeKeyframe(_ keyframe: Keyframe) {
        keyframes.removeAll { $0.id == keyframe.id }
        currentVideo?.cropConfiguration.keyframes = keyframes
        selectedKeyframeIDs.remove(keyframe.id)
    }

    func removeKeyframe(at timestamp: Double) {
        if let keyframe = keyframes.first(where: { abs($0.timestamp - timestamp) < 0.1 }) {
            removeKeyframe(keyframe)
        }
    }

    func deleteSelected() {
        let idsToRemove = selectedKeyframeIDs
        keyframes.removeAll { idsToRemove.contains($0.id) }
        currentVideo?.cropConfiguration.keyframes = keyframes
        selectedKeyframeIDs.removeAll()
    }

    // MARK: - Move

    func moveKeyframe(_ keyframe: Keyframe, to newTimestamp: Double) {
        // Snap to nearest frame boundary
        let snappedTimestamp = snapToFrame(max(0, newTimestamp))
        
        // Check for collision
        let hasCollision = keyframes.contains { other in
            other.id != keyframe.id && abs(other.timestamp - snappedTimestamp) < 0.01
        }

        if !hasCollision {
            keyframe.timestamp = snappedTimestamp
            sortKeyframes()
        }
    }

    func sortKeyframes() {
        keyframes.sort { $0.timestamp < $1.timestamp }
        currentVideo?.cropConfiguration.keyframes = keyframes
    }

    // MARK: - Update

    func updateCurrentKeyframe() {
        guard let keyframe = selectedKeyframe, let cropEditor = cropEditor else { return }

        keyframe.cropRect = cropEditor.cropRect
        keyframe.edgeInsets = cropEditor.edgeInsets
        keyframe.circleCenter = cropEditor.circleCenter
        keyframe.circleRadius = cropEditor.circleRadius

        // Update freehand path data
        keyframe.freehandPathData = cropEditor.freehandPathData

        // Update AI mask data
        if cropEditor.mode == .ai || cropEditor.aiMaskData != nil {
            keyframe.aiMaskData = cropEditor.aiMaskData
            keyframe.aiPromptPoints = cropEditor.aiPromptPoints.isEmpty ? nil : cropEditor.aiPromptPoints
            keyframe.aiBoundingBox = cropEditor.aiBoundingBox.width > 0 ? cropEditor.aiBoundingBox : nil
        }

        currentVideo?.cropConfiguration.keyframes = keyframes
        
        // Toggle to force view refresh
        updateTrigger.toggle()
    }

    func applyKeyframeState(at timestamp: Double) {
        guard let cropEditor = cropEditor, keyframesEnabled, !keyframes.isEmpty else { return }

        // Don't apply keyframe state while user is actively dragging/editing
        guard !cropEditor.isDragging else { return }

        // If a keyframe is selected, apply that keyframe's exact values
        // This ensures clicking on a keyframe marker shows its exact crop state
        if let selectedID = selectedKeyframeIDs.first,
           let selectedKeyframe = keyframes.first(where: { $0.id == selectedID }) {
            applyKeyframeToEditor(selectedKeyframe)
            return
        }

        let state = KeyframeInterpolator.shared.interpolate(
            keyframes: keyframes,
            at: timestamp,
            mode: cropEditor.mode
        )

        cropEditor.cropRect = state.cropRect
        cropEditor.edgeInsets = state.edgeInsets
        cropEditor.circleCenter = state.circleCenter
        cropEditor.circleRadius = state.circleRadius

        // Also update AI mask data for AI mode
        if cropEditor.mode == .ai {
            // Apply interpolated mask data (hold interpolation - uses nearest keyframe's mask)
            cropEditor.aiMaskData = state.aiMaskData
            cropEditor.aiBoundingBox = state.aiBoundingBox
            // Sync cropRect with aiBoundingBox in AI mode
            if state.aiBoundingBox.width > 0 {
                cropEditor.cropRect = state.aiBoundingBox
            }
        }
    }
    // MARK: - Query

    func hasKeyframe(at timestamp: Double, tolerance: Double = 0.1) -> Bool {
        keyframes.contains { abs($0.timestamp - timestamp) < tolerance }
    }

    func nearestKeyframe(to timestamp: Double) -> Keyframe? {
        keyframes.min { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) }
    }

    /// Returns true if the given timestamp falls within an "absent" keyframe's duration
    /// (i.e., between an absent keyframe and the next keyframe, or to the end if it's the last)
    func isAbsent(at timestamp: Double) -> Bool {
        guard keyframesEnabled, !keyframes.isEmpty else { return false }
        
        let sorted = keyframes.sorted { $0.timestamp < $1.timestamp }
        
        // Find the keyframe that applies at this timestamp (the one at or just before)
        if let activeKeyframe = sorted.last(where: { $0.timestamp <= timestamp }) {
            return activeKeyframe.isAbsent
        }
        
        // Before first keyframe - check if first keyframe is absent
        // (though typically we'd use the first keyframe's state)
        return sorted.first?.isAbsent ?? false
    }

    func autoCreateKeyframe(at timestamp: Double, tolerance: Double = 0.1) {
        guard keyframesEnabled, let cropEditor = cropEditor else { return }

        // If a keyframe is selected, update that keyframe instead of creating a new one
        // This allows editing the bounding box for the selected keyframe's duration
        if let selectedID = selectedKeyframeIDs.first,
           let selectedKeyframe = keyframes.first(where: { $0.id == selectedID }) {
            updateKeyframe(selectedKeyframe, from: cropEditor)
            return
        }

        if let existingKeyframe = keyframes.first(where: { abs($0.timestamp - timestamp) < tolerance }) {
            // Update all crop state properties
            updateKeyframe(existingKeyframe, from: cropEditor)
            selectedKeyframeIDs = [existingKeyframe.id]
        } else {
            addKeyframe(at: timestamp)
        }
    }
    
    /// Updates a keyframe with the current crop editor state
    private func updateKeyframe(_ keyframe: Keyframe, from cropEditor: CropEditorViewModel) {
        keyframe.cropRect = cropEditor.cropRect
        keyframe.edgeInsets = cropEditor.edgeInsets
        keyframe.circleCenter = cropEditor.circleCenter
        keyframe.circleRadius = cropEditor.circleRadius

        // Update freehand path data
        keyframe.freehandPathData = cropEditor.freehandPathData

        // Update AI mask data
        if cropEditor.mode == .ai || cropEditor.aiMaskData != nil {
            keyframe.aiMaskData = cropEditor.aiMaskData
            keyframe.aiPromptPoints = cropEditor.aiPromptPoints.isEmpty ? nil : cropEditor.aiPromptPoints
            keyframe.aiBoundingBox = cropEditor.aiBoundingBox.width > 0 ? cropEditor.aiBoundingBox : nil
        }

        currentVideo?.cropConfiguration.keyframes = keyframes
    }
}

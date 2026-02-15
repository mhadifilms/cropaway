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
    @Published var keyframesEnabled: Bool = false
    @Published var selectedKeyframeIDs: Set<UUID> = []

    private var currentVideo: VideoItem?
    private var currentClip: TimelineClip?
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
    
    /// Get the crop configuration being edited (works for both VideoItem and TimelineClip)
    private var cropConfiguration: CropConfiguration? {
        if let video = currentVideo {
            return video.cropConfiguration
        } else if let clip = currentClip {
            return clip.cropConfiguration
        }
        return nil
    }

    func bind(to video: VideoItem, cropEditor: CropEditorViewModel) {
        cancellables.removeAll()
        currentVideo = video
        currentClip = nil
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
    
    /// Bind to a TimelineClip (timeline-native approach)
    func bind(to clip: TimelineClip, cropEditor: CropEditorViewModel) {
        cancellables.removeAll()
        currentClip = clip
        currentVideo = nil
        self.cropEditor = cropEditor

        let config = clip.cropConfiguration

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
        }
    }

    func selectKeyframe(at timestamp: Double) {
        if let kf = keyframes.first(where: { abs($0.timestamp - timestamp) < 0.1 }) {
            selectedKeyframeIDs = [kf.id]
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

    func addKeyframe(at timestamp: Double) {
        guard let cropEditor = cropEditor else { return }

        let keyframe = Keyframe(
            timestamp: timestamp,
            cropRect: cropEditor.cropRect,
            edgeInsets: cropEditor.edgeInsets,
            circleCenter: cropEditor.circleCenter,
            circleRadius: cropEditor.circleRadius
        )

        // Include freehand path data
        keyframe.freehandPathData = cropEditor.freehandPathData

        // Include AI mask data
        if cropEditor.mode == .ai || cropEditor.aiMaskData != nil {
            keyframe.aiMaskData = cropEditor.aiMaskData
            keyframe.aiPromptPoints = cropEditor.aiPromptPoints.isEmpty ? nil : cropEditor.aiPromptPoints
            keyframe.aiBoundingBox = cropEditor.aiBoundingBox.width > 0 ? cropEditor.aiBoundingBox : nil
        }

        // Insert in sorted order
        if let insertIndex = keyframes.firstIndex(where: { $0.timestamp > timestamp }) {
            keyframes.insert(keyframe, at: insertIndex)
        } else {
            keyframes.append(keyframe)
        }

        cropConfiguration?.keyframes = keyframes
        selectedKeyframeIDs = [keyframe.id]
    }

    func removeKeyframe(_ keyframe: Keyframe) {
        keyframes.removeAll { $0.id == keyframe.id }
        cropConfiguration?.keyframes = keyframes
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
        cropConfiguration?.keyframes = keyframes
        selectedKeyframeIDs.removeAll()
    }

    // MARK: - Move

    func moveKeyframe(_ keyframe: Keyframe, to newTimestamp: Double) {
        // Check for collision
        let hasCollision = keyframes.contains { other in
            other.id != keyframe.id && abs(other.timestamp - newTimestamp) < 0.05
        }

        if !hasCollision {
            keyframe.timestamp = max(0, newTimestamp)
            sortKeyframes()
        }
    }

    func sortKeyframes() {
        keyframes.sort { $0.timestamp < $1.timestamp }
        cropConfiguration?.keyframes = keyframes
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

        cropConfiguration?.keyframes = keyframes
    }

    func applyKeyframeState(at timestamp: Double) {
        guard let cropEditor = cropEditor else { return }

        if keyframesEnabled && keyframes.count >= 2 {
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
    }
    // MARK: - Query

    func hasKeyframe(at timestamp: Double, tolerance: Double = 0.1) -> Bool {
        keyframes.contains { abs($0.timestamp - timestamp) < tolerance }
    }

    func nearestKeyframe(to timestamp: Double) -> Keyframe? {
        keyframes.min { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) }
    }

    func autoCreateKeyframe(at timestamp: Double, tolerance: Double = 0.1) {
        guard keyframesEnabled, let cropEditor = cropEditor else { return }

        if let existingKeyframe = keyframes.first(where: { abs($0.timestamp - timestamp) < tolerance }) {
            // Update all crop state properties
            existingKeyframe.cropRect = cropEditor.cropRect
            existingKeyframe.edgeInsets = cropEditor.edgeInsets
            existingKeyframe.circleCenter = cropEditor.circleCenter
            existingKeyframe.circleRadius = cropEditor.circleRadius

            // Update freehand path data
            existingKeyframe.freehandPathData = cropEditor.freehandPathData

            // Update AI mask data
            if cropEditor.mode == .ai || cropEditor.aiMaskData != nil {
                existingKeyframe.aiMaskData = cropEditor.aiMaskData
                existingKeyframe.aiPromptPoints = cropEditor.aiPromptPoints.isEmpty ? nil : cropEditor.aiPromptPoints
                existingKeyframe.aiBoundingBox = cropEditor.aiBoundingBox.width > 0 ? cropEditor.aiBoundingBox : nil
            }

            cropConfiguration?.keyframes = keyframes
            selectedKeyframeIDs = [existingKeyframe.id]
        } else {
            addKeyframe(at: timestamp)
        }
    }
}

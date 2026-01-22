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
    @Published var selectedKeyframe: Keyframe?

    private var currentVideo: VideoItem?
    private var cropEditor: CropEditorViewModel?
    private var cancellables = Set<AnyCancellable>()

    func bind(to video: VideoItem, cropEditor: CropEditorViewModel) {
        cancellables.removeAll()
        currentVideo = video
        self.cropEditor = cropEditor

        let config = video.cropConfiguration

        // Sync from config
        keyframes = config.keyframes
        keyframesEnabled = config.keyframesEnabled

        // Sync changes back
        $keyframesEnabled
            .dropFirst()
            .sink { config.keyframesEnabled = $0 }
            .store(in: &cancellables)
    }

    func addKeyframe(at timestamp: Double) {
        guard let cropEditor = cropEditor else { return }

        let keyframe = Keyframe(
            timestamp: timestamp,
            cropRect: cropEditor.cropRect,
            edgeInsets: cropEditor.edgeInsets,
            circleCenter: cropEditor.circleCenter,
            circleRadius: cropEditor.circleRadius
        )

        // Insert in sorted order
        if let insertIndex = keyframes.firstIndex(where: { $0.timestamp > timestamp }) {
            keyframes.insert(keyframe, at: insertIndex)
        } else {
            keyframes.append(keyframe)
        }

        currentVideo?.cropConfiguration.keyframes = keyframes
        selectedKeyframe = keyframe
    }

    func removeKeyframe(_ keyframe: Keyframe) {
        keyframes.removeAll { $0.id == keyframe.id }
        currentVideo?.cropConfiguration.keyframes = keyframes

        if selectedKeyframe?.id == keyframe.id {
            selectedKeyframe = nil
        }
    }

    func removeKeyframe(at timestamp: Double) {
        if let keyframe = keyframes.first(where: { abs($0.timestamp - timestamp) < 0.1 }) {
            removeKeyframe(keyframe)
        }
    }

    func selectKeyframe(_ keyframe: Keyframe) {
        selectedKeyframe = keyframe
    }

    func selectKeyframe(at timestamp: Double) {
        selectedKeyframe = keyframes.first { abs($0.timestamp - timestamp) < 0.1 }
    }

    func updateCurrentKeyframe() {
        guard let keyframe = selectedKeyframe, let cropEditor = cropEditor else { return }

        keyframe.cropRect = cropEditor.cropRect
        keyframe.edgeInsets = cropEditor.edgeInsets
        keyframe.circleCenter = cropEditor.circleCenter
        keyframe.circleRadius = cropEditor.circleRadius

        currentVideo?.cropConfiguration.keyframes = keyframes
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
        }
    }

    func hasKeyframe(at timestamp: Double, tolerance: Double = 0.1) -> Bool {
        keyframes.contains { abs($0.timestamp - timestamp) < tolerance }
    }

    func nearestKeyframe(to timestamp: Double) -> Keyframe? {
        keyframes.min { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) }
    }

    /// Automatically creates or updates a keyframe at the given timestamp.
    /// This is called when keyframes are enabled and the user finishes editing the crop.
    /// - Parameter timestamp: The current playback time
    /// - Parameter tolerance: Time tolerance for considering a keyframe to be at the same position (default 0.1 seconds)
    func autoCreateKeyframe(at timestamp: Double, tolerance: Double = 0.1) {
        guard keyframesEnabled, let cropEditor = cropEditor else { return }

        // Check if a keyframe already exists at this time (within tolerance)
        if let existingKeyframe = keyframes.first(where: { abs($0.timestamp - timestamp) < tolerance }) {
            // Update the existing keyframe with current crop state
            existingKeyframe.cropRect = cropEditor.cropRect
            existingKeyframe.edgeInsets = cropEditor.edgeInsets
            existingKeyframe.circleCenter = cropEditor.circleCenter
            existingKeyframe.circleRadius = cropEditor.circleRadius

            currentVideo?.cropConfiguration.keyframes = keyframes
            selectedKeyframe = existingKeyframe
        } else {
            // Create a new keyframe at this timestamp
            addKeyframe(at: timestamp)
        }
    }
}

//
//  CropConfiguration.swift
//  cropaway
//

import Combine
import Foundation
import CoreGraphics

final class CropConfiguration: ObservableObject {
    @Published var mode: CropMode = .rectangle
    @Published var isEnabled: Bool = true

    // Rectangle crop (normalized 0-1)
    @Published var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    // Edge-based crop (normalized 0-1)
    @Published var edgeInsets: EdgeInsets = EdgeInsets()

    // Circle crop (normalized)
    @Published var circleCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var circleRadius: Double = 0.4

    // Freehand mask (serialized path)
    @Published var freehandPathData: Data?
    @Published var freehandPoints: [CGPoint] = []

    // AI mask (SAM3 segmentation)
    @Published var aiMaskData: Data?
    @Published var aiPromptPoints: [AIPromptPoint] = []
    @Published var aiTextPrompt: String?
    @Published var aiObjectId: String?
    @Published var aiBoundingBox: CGRect = .zero
    @Published var aiConfidence: Double = 0

    // Keyframes for animation
    @Published var keyframes: [Keyframe] = []
    @Published var keyframesEnabled: Bool = false

    // Export settings (per-video)
    @Published var preserveWidth: Bool = true
    @Published var enableAlphaChannel: Bool = false

    init() {}

    var hasKeyframes: Bool {
        keyframesEnabled && keyframes.count > 1
    }

    /// Returns true if any crop changes have been made from the default full-frame state
    var hasCropChanges: Bool {
        switch mode {
        case .rectangle:
            // Check if rectangle differs from full frame
            let isFullFrame = cropRect.origin.x < 0.001 &&
                              cropRect.origin.y < 0.001 &&
                              cropRect.width > 0.999 &&
                              cropRect.height > 0.999
            return !isFullFrame || hasKeyframes
        case .circle:
            // Circle mode always implies masking (parts will be black/transparent)
            return true
        case .freehand:
            // Freehand with points implies masking
            return freehandPoints.count >= 3 || hasKeyframes
        case .ai:
            // AI mode has changes if mask data exists
            return aiMaskData != nil || hasKeyframes
        }
    }

    // Get the effective crop rect for the current mode
    var effectiveCropRect: CGRect {
        switch mode {
        case .rectangle:
            return cropRect
        case .circle:
            // Bounding box of circle
            let diameter = circleRadius * 2
            return CGRect(
                x: circleCenter.x - circleRadius,
                y: circleCenter.y - circleRadius,
                width: diameter,
                height: diameter
            )
        case .freehand:
            // Bounding box of path
            return cropRect // Simplified for now
        case .ai:
            // Use AI bounding box if available, otherwise full frame
            return aiBoundingBox.width > 0 ? aiBoundingBox : CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    func addKeyframe(at timestamp: Double) {
        let keyframe = Keyframe(
            timestamp: timestamp,
            cropRect: cropRect,
            edgeInsets: edgeInsets,
            circleCenter: circleCenter,
            circleRadius: circleRadius
        )
        keyframe.freehandPathData = freehandPathData

        // Insert in sorted order
        if let insertIndex = keyframes.firstIndex(where: { $0.timestamp > timestamp }) {
            keyframes.insert(keyframe, at: insertIndex)
        } else {
            keyframes.append(keyframe)
        }
    }

    func removeKeyframe(at timestamp: Double) {
        keyframes.removeAll { abs($0.timestamp - timestamp) < 0.001 }
    }

    func updateCurrentKeyframe(at timestamp: Double) {
        guard let keyframe = keyframes.first(where: { abs($0.timestamp - timestamp) < 0.001 }) else {
            return
        }

        keyframe.cropRect = cropRect
        keyframe.edgeInsets = edgeInsets
        keyframe.circleCenter = circleCenter
        keyframe.circleRadius = circleRadius
        keyframe.freehandPathData = freehandPathData
    }

    func reset() {
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        edgeInsets = EdgeInsets()
        circleCenter = CGPoint(x: 0.5, y: 0.5)
        circleRadius = 0.4
        freehandPathData = nil
        freehandPoints = []
        // Reset AI mask
        aiMaskData = nil
        aiPromptPoints = []
        aiTextPrompt = nil
        aiObjectId = nil
        aiBoundingBox = .zero
        aiConfidence = 0
        keyframes = []
        keyframesEnabled = false
        // Note: Don't reset preserveWidth and enableAlphaChannel as they're user preferences per video
    }
}

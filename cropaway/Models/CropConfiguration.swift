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

    // AI mask (fal.ai video tracking)
    @Published var aiMaskData: Data?
    @Published var aiPromptPoints: [AIPromptPoint] = []
    @Published var aiTextPrompt: String?
    @Published var aiObjectId: String?
    @Published var aiBoundingBox: CGRect = .zero
    @Published var aiConfidence: Double = 0
    @Published var aiInteractionMode: AIInteractionMode = .point

    // Keyframes for animation
    @Published var keyframes: [Keyframe] = []
    @Published var keyframesEnabled: Bool = false

    // Frames where object is absent (timestamp ranges in seconds)
    @Published var absenceRanges: [AbsenceRange] = []

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
            return !isFullFrame || hasKeyframes || !absenceRanges.isEmpty
        case .circle:
            // Circle mode always implies masking (parts will be black/transparent)
            return true
        case .freehand:
            // Freehand with points implies masking
            return freehandPoints.count >= 3 || hasKeyframes || !absenceRanges.isEmpty
        case .ai:
            // AI mode has changes if mask data exists
            return aiMaskData != nil || hasKeyframes || !absenceRanges.isEmpty
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

        // Include AI mask data if in AI mode or if mask data exists
        if mode == .ai || aiMaskData != nil {
            keyframe.aiMaskData = aiMaskData
            keyframe.aiPromptPoints = aiPromptPoints.isEmpty ? nil : aiPromptPoints
            keyframe.aiBoundingBox = aiBoundingBox.width > 0 ? aiBoundingBox : nil
        }

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

        // Update AI mask data
        if mode == .ai || aiMaskData != nil {
            keyframe.aiMaskData = aiMaskData
            keyframe.aiPromptPoints = aiPromptPoints.isEmpty ? nil : aiPromptPoints
            keyframe.aiBoundingBox = aiBoundingBox.width > 0 ? aiBoundingBox : nil
        }
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
        absenceRanges = []
        // Note: Don't reset preserveWidth and enableAlphaChannel as they're user preferences per video
    }

    /// Validate and clamp all crop values to valid ranges
    func validateAndClamp() {
        // Clamp rectangle to 0-1 normalized coordinates
        cropRect = CGRect(
            x: max(0, min(1, cropRect.origin.x)),
            y: max(0, min(1, cropRect.origin.y)),
            width: max(0.01, min(1 - cropRect.origin.x, cropRect.width)),
            height: max(0.01, min(1 - cropRect.origin.y, cropRect.height))
        )

        // Clamp circle center to 0-1 and radius to valid range
        circleCenter = CGPoint(
            x: max(0, min(1, circleCenter.x)),
            y: max(0, min(1, circleCenter.y))
        )
        circleRadius = max(0.01, min(0.5, circleRadius))

        // Clamp freehand points to 0-1
        freehandPoints = freehandPoints.map { point in
            CGPoint(
                x: max(0, min(1, point.x)),
                y: max(0, min(1, point.y))
            )
        }

        // Clamp AI bounding box
        if aiBoundingBox.width > 0 {
            aiBoundingBox = CGRect(
                x: max(0, min(1, aiBoundingBox.origin.x)),
                y: max(0, min(1, aiBoundingBox.origin.y)),
                width: max(0.01, min(1 - aiBoundingBox.origin.x, aiBoundingBox.width)),
                height: max(0.01, min(1 - aiBoundingBox.origin.y, aiBoundingBox.height))
            )
        }
    }

    /// Returns true if all crop values are within valid normalized 0-1 range
    var isValid: Bool {
        // Check rectangle
        let rectValid = cropRect.origin.x >= 0 && cropRect.origin.x <= 1 &&
                        cropRect.origin.y >= 0 && cropRect.origin.y <= 1 &&
                        cropRect.width > 0 && cropRect.origin.x + cropRect.width <= 1 &&
                        cropRect.height > 0 && cropRect.origin.y + cropRect.height <= 1

        // Check circle
        let circleValid = circleCenter.x >= 0 && circleCenter.x <= 1 &&
                          circleCenter.y >= 0 && circleCenter.y <= 1 &&
                          circleRadius > 0 && circleRadius <= 0.5

        // Check freehand points
        let freehandValid = freehandPoints.allSatisfy { point in
            point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1
        }

        return rectValid && circleValid && freehandValid
    }

    func addAbsenceRange(start: Double, end: Double) {
        let normalizedStart = min(start, end)
        let normalizedEnd = max(start, end)
        guard normalizedEnd >= normalizedStart else { return }

        var ranges = absenceRanges
        ranges.append(AbsenceRange(start: normalizedStart, end: normalizedEnd))

        // Merge overlapping ranges
        ranges.sort { $0.start < $1.start }
        var merged: [AbsenceRange] = []
        for range in ranges {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1] = AbsenceRange(start: last.start, end: max(last.end, range.end))
            } else {
                merged.append(range)
            }
        }
        absenceRanges = merged
    }

    func clearAbsenceRanges() {
        absenceRanges = []
    }

    func removeAbsenceRange(containing timestamp: Double) {
        absenceRanges.removeAll { $0.contains(timestamp) }
    }

    func isAbsent(at timestamp: Double) -> Bool {
        absenceRanges.contains { $0.contains(timestamp) }
    }
}

struct AbsenceRange: Codable, Equatable {
    let start: Double
    let end: Double

    func contains(_ timestamp: Double) -> Bool {
        timestamp >= start && timestamp <= end
    }
}

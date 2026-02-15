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

    // Export settings (per-video)
    @Published var preserveWidth: Bool = true
    @Published var enableAlphaChannel: Bool = false
    
    // Timeline in/out points for export range
    @Published var inPoint: Double?
    @Published var outPoint: Double?

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
    
    /// Create a deep copy of this configuration
    func copy() -> CropConfiguration {
        let copy = CropConfiguration()
        copy.mode = mode
        copy.isEnabled = isEnabled
        copy.cropRect = cropRect
        copy.edgeInsets = edgeInsets
        copy.circleCenter = circleCenter
        copy.circleRadius = circleRadius
        copy.freehandPathData = freehandPathData
        copy.freehandPoints = freehandPoints
        copy.aiMaskData = aiMaskData
        copy.aiPromptPoints = aiPromptPoints
        copy.aiTextPrompt = aiTextPrompt
        copy.aiObjectId = aiObjectId
        copy.aiBoundingBox = aiBoundingBox
        copy.aiConfidence = aiConfidence
        copy.aiInteractionMode = aiInteractionMode
        copy.keyframes = keyframes.map { $0.copy() }
        copy.keyframesEnabled = keyframesEnabled
        copy.preserveWidth = preserveWidth
        copy.enableAlphaChannel = enableAlphaChannel
        copy.inPoint = inPoint
        copy.outPoint = outPoint
        return copy
    }
}

// MARK: - Codable

extension CropConfiguration: Codable {
    enum CodingKeys: String, CodingKey {
        case mode, isEnabled
        case cropRect, edgeInsets
        case circleCenter, circleRadius
        case freehandPathData, freehandPoints
        case aiMaskData, aiPromptPoints, aiTextPrompt, aiObjectId
        case aiBoundingBox, aiConfidence, aiInteractionMode
        case keyframes, keyframesEnabled
        case preserveWidth, enableAlphaChannel
        case inPoint, outPoint
    }
    
    convenience init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        mode = try container.decode(CropMode.self, forKey: .mode)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        
        cropRect = try container.decode(CGRect.self, forKey: .cropRect)
        edgeInsets = try container.decode(EdgeInsets.self, forKey: .edgeInsets)
        
        circleCenter = try container.decode(CGPoint.self, forKey: .circleCenter)
        circleRadius = try container.decode(Double.self, forKey: .circleRadius)
        
        freehandPathData = try container.decodeIfPresent(Data.self, forKey: .freehandPathData)
        freehandPoints = try container.decode([CGPoint].self, forKey: .freehandPoints)
        
        aiMaskData = try container.decodeIfPresent(Data.self, forKey: .aiMaskData)
        aiPromptPoints = try container.decode([AIPromptPoint].self, forKey: .aiPromptPoints)
        aiTextPrompt = try container.decodeIfPresent(String.self, forKey: .aiTextPrompt)
        aiObjectId = try container.decodeIfPresent(String.self, forKey: .aiObjectId)
        aiBoundingBox = try container.decode(CGRect.self, forKey: .aiBoundingBox)
        aiConfidence = try container.decode(Double.self, forKey: .aiConfidence)
        aiInteractionMode = try container.decode(AIInteractionMode.self, forKey: .aiInteractionMode)
        
        keyframes = try container.decode([Keyframe].self, forKey: .keyframes)
        keyframesEnabled = try container.decode(Bool.self, forKey: .keyframesEnabled)
        
        preserveWidth = try container.decode(Bool.self, forKey: .preserveWidth)
        enableAlphaChannel = try container.decode(Bool.self, forKey: .enableAlphaChannel)
        
        inPoint = try container.decodeIfPresent(Double.self, forKey: .inPoint)
        outPoint = try container.decodeIfPresent(Double.self, forKey: .outPoint)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(mode, forKey: .mode)
        try container.encode(isEnabled, forKey: .isEnabled)
        
        try container.encode(cropRect, forKey: .cropRect)
        try container.encode(edgeInsets, forKey: .edgeInsets)
        
        try container.encode(circleCenter, forKey: .circleCenter)
        try container.encode(circleRadius, forKey: .circleRadius)
        
        try container.encodeIfPresent(freehandPathData, forKey: .freehandPathData)
        try container.encode(freehandPoints, forKey: .freehandPoints)
        
        try container.encodeIfPresent(aiMaskData, forKey: .aiMaskData)
        try container.encode(aiPromptPoints, forKey: .aiPromptPoints)
        try container.encodeIfPresent(aiTextPrompt, forKey: .aiTextPrompt)
        try container.encodeIfPresent(aiObjectId, forKey: .aiObjectId)
        try container.encode(aiBoundingBox, forKey: .aiBoundingBox)
        try container.encode(aiConfidence, forKey: .aiConfidence)
        try container.encode(aiInteractionMode, forKey: .aiInteractionMode)
        
        try container.encode(keyframes, forKey: .keyframes)
        try container.encode(keyframesEnabled, forKey: .keyframesEnabled)
        
        try container.encode(preserveWidth, forKey: .preserveWidth)
        try container.encode(enableAlphaChannel, forKey: .enableAlphaChannel)
        
        try container.encodeIfPresent(inPoint, forKey: .inPoint)
        try container.encodeIfPresent(outPoint, forKey: .outPoint)
    }
}

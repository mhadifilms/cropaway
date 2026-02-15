//
//  Keyframe.swift
//  cropaway
//

import Combine
import Foundation
import CoreGraphics

enum KeyframeInterpolation: String, Codable, CaseIterable, Identifiable {
    case linear = "linear"
    case easeIn = "easeIn"
    case easeOut = "easeOut"
    case easeInOut = "easeInOut"
    case hold = "hold"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In/Out"
        case .hold: return "Hold"
        }
    }
}

final class Keyframe: Identifiable, ObservableObject {
    let id: UUID
    @Published var timestamp: Double

    // Crop state at this keyframe (normalized 0-1 coordinates)
    @Published var cropRect: CGRect
    @Published var edgeInsets: EdgeInsets
    @Published var circleCenter: CGPoint
    @Published var circleRadius: Double
    @Published var freehandPathData: Data?

    // AI mask data for this keyframe
    @Published var aiMaskData: Data?
    @Published var aiPromptPoints: [AIPromptPoint]?
    @Published var aiBoundingBox: CGRect?

    // Interpolation to next keyframe
    @Published var interpolation: KeyframeInterpolation

    init(
        timestamp: Double,
        cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        edgeInsets: EdgeInsets = EdgeInsets(),
        circleCenter: CGPoint = CGPoint(x: 0.5, y: 0.5),
        circleRadius: Double = 0.4,
        interpolation: KeyframeInterpolation = .linear
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.cropRect = cropRect
        self.edgeInsets = edgeInsets
        self.circleCenter = circleCenter
        self.circleRadius = circleRadius
        self.interpolation = interpolation
    }

    func copy() -> Keyframe {
        let kf = Keyframe(
            timestamp: timestamp,
            cropRect: cropRect,
            edgeInsets: edgeInsets,
            circleCenter: circleCenter,
            circleRadius: circleRadius,
            interpolation: interpolation
        )
        kf.freehandPathData = freehandPathData
        kf.aiMaskData = aiMaskData
        kf.aiPromptPoints = aiPromptPoints
        kf.aiBoundingBox = aiBoundingBox
        return kf
    }
}

// MARK: - Codable

extension Keyframe: Codable {
    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case cropRect, edgeInsets
        case circleCenter, circleRadius
        case freehandPathData
        case aiMaskData, aiPromptPoints, aiBoundingBox
        case interpolation
    }
    
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try container.decode(Double.self, forKey: .timestamp)
        let cropRect = try container.decode(CGRect.self, forKey: .cropRect)
        let edgeInsets = try container.decode(EdgeInsets.self, forKey: .edgeInsets)
        let circleCenter = try container.decode(CGPoint.self, forKey: .circleCenter)
        let circleRadius = try container.decode(Double.self, forKey: .circleRadius)
        let interpolation = try container.decode(KeyframeInterpolation.self, forKey: .interpolation)
        
        self.init(
            timestamp: timestamp,
            cropRect: cropRect,
            edgeInsets: edgeInsets,
            circleCenter: circleCenter,
            circleRadius: circleRadius,
            interpolation: interpolation
        )
        
        // Decode optional fields
        self.freehandPathData = try container.decodeIfPresent(Data.self, forKey: .freehandPathData)
        self.aiMaskData = try container.decodeIfPresent(Data.self, forKey: .aiMaskData)
        self.aiPromptPoints = try container.decodeIfPresent([AIPromptPoint].self, forKey: .aiPromptPoints)
        self.aiBoundingBox = try container.decodeIfPresent(CGRect.self, forKey: .aiBoundingBox)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(cropRect, forKey: .cropRect)
        try container.encode(edgeInsets, forKey: .edgeInsets)
        try container.encode(circleCenter, forKey: .circleCenter)
        try container.encode(circleRadius, forKey: .circleRadius)
        try container.encodeIfPresent(freehandPathData, forKey: .freehandPathData)
        try container.encodeIfPresent(aiMaskData, forKey: .aiMaskData)
        try container.encodeIfPresent(aiPromptPoints, forKey: .aiPromptPoints)
        try container.encodeIfPresent(aiBoundingBox, forKey: .aiBoundingBox)
        try container.encode(interpolation, forKey: .interpolation)
    }
}

struct EdgeInsets: Equatable, Codable {
    var top: Double = 0
    var left: Double = 0
    var bottom: Double = 0
    var right: Double = 0

    init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        // Clamp values to valid 0-1 range
        self.top = top.clamped(to: 0...1)
        self.left = left.clamped(to: 0...1)
        self.bottom = bottom.clamped(to: 0...1)
        self.right = right.clamped(to: 0...1)
    }

    var cropRect: CGRect {
        CGRect(
            x: left,
            y: top,
            width: max(0, 1.0 - left - right),
            height: max(0, 1.0 - top - bottom)
        )
    }

    /// Returns true if insets produce a valid (non-negative size) crop area
    var isValid: Bool {
        left + right < 1.0 && top + bottom < 1.0
    }
}

// MARK: - Double Clamping Extension

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

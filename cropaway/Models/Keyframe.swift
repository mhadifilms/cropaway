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
        return kf
    }
}

struct EdgeInsets: Equatable {
    var top: Double = 0
    var left: Double = 0
    var bottom: Double = 0
    var right: Double = 0

    init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    var cropRect: CGRect {
        CGRect(
            x: left,
            y: top,
            width: 1.0 - left - right,
            height: 1.0 - top - bottom
        )
    }
}

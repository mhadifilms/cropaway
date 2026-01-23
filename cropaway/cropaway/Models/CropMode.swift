//
//  CropMode.swift
//  cropaway
//

import Foundation

enum CropMode: String, Codable, CaseIterable, Identifiable {
    case rectangle = "rectangle"
    case circle = "circle"
    case freehand = "freehand"
    case ai = "ai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .freehand: return "Custom Mask"
        case .ai: return "AI Mask"
        }
    }

    var iconName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .freehand: return "scribble.variable"
        case .ai: return "wand.and.stars"
        }
    }
}

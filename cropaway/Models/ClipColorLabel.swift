//
//  ClipColorLabel.swift
//  cropaway
//
//  PHASE 10: Color labels for clip organization
//

import Foundation
import AppKit

/// Color labels for organizing timeline clips
enum ClipColorLabel: String, Codable, CaseIterable {
    case none = "None"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case gray = "Gray"
    
    /// The display color for this label
    var color: NSColor {
        switch self {
        case .none: return .clear
        case .red: return NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.3)
        case .orange: return NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 0.3)
        case .yellow: return NSColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 0.3)
        case .green: return NSColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.3)
        case .blue: return NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.3)
        case .purple: return NSColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 0.3)
        case .pink: return NSColor(red: 1.0, green: 0.4, blue: 0.7, alpha: 0.3)
        case .gray: return NSColor(white: 0.5, alpha: 0.3)
        }
    }
    
    /// Stronger color for borders/accents
    var accentColor: NSColor {
        switch self {
        case .none: return .clear
        case .red: return NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.6)
        case .orange: return NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 0.6)
        case .yellow: return NSColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 0.6)
        case .green: return NSColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.6)
        case .blue: return NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.6)
        case .purple: return NSColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 0.6)
        case .pink: return NSColor(red: 1.0, green: 0.4, blue: 0.7, alpha: 0.6)
        case .gray: return NSColor(white: 0.5, alpha: 0.6)
        }
    }
}

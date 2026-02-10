//
//  ClipTransition.swift
//  cropaway
//

import Foundation
import Combine

/// Type of transition between two clips in a sequence
enum TransitionType: String, Codable, CaseIterable, Identifiable {
    case cut = "cut"
    case fade = "fade"
    case fadeToBlack = "fadeToBlack"
    case opticalFlow = "opticalFlow"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cut: return "Cut"
        case .fade: return "Fade"
        case .fadeToBlack: return "Fade to Black"
        case .opticalFlow: return "Morph"
        }
    }

    var iconName: String {
        switch self {
        case .cut: return "scissors"
        case .fade: return "circle.lefthalf.filled"
        case .fadeToBlack: return "circle.bottomhalf.filled"
        case .opticalFlow: return "wand.and.rays"
        }
    }

    /// Whether this transition requires a duration parameter
    var requiresDuration: Bool {
        self != .cut
    }

    /// Default duration for this transition type
    var defaultDuration: Double {
        switch self {
        case .cut: return 0
        case .fade, .fadeToBlack: return 0.5
        case .opticalFlow: return 0.5
        }
    }

    /// Whether this transition type is available on the current macOS version
    var isAvailable: Bool {
        switch self {
        case .cut, .fade, .fadeToBlack:
            return true
        case .opticalFlow:
            if #available(macOS 26.0, *) {
                return true
            } else {
                return false
            }
        }
    }

    /// Available transition types for the current macOS version
    static var availableTypes: [TransitionType] {
        allCases.filter { $0.isAvailable }
    }
}

/// Represents a transition between two clips in a timeline sequence
final class ClipTransition: Identifiable, ObservableObject, Codable {
    let id: UUID

    /// Type of transition (cut, fade, fade to black, or optical flow morph)
    @Published var type: TransitionType

    /// Duration of the transition in seconds (used for all types except cut)
    /// Range: 0.1 to 2.0 seconds
    @Published var duration: Double

    /// Index of the clip this transition follows (transition occurs after this clip)
    let afterClipIndex: Int

    init(
        id: UUID = UUID(),
        type: TransitionType = .cut,
        duration: Double = 0.5,
        afterClipIndex: Int
    ) {
        self.id = id
        self.type = type
        self.duration = max(0.1, min(2.0, duration))
        self.afterClipIndex = afterClipIndex
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, type, duration, afterClipIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(TransitionType.self, forKey: .type)
        duration = try container.decode(Double.self, forKey: .duration)
        afterClipIndex = try container.decode(Int.self, forKey: .afterClipIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(duration, forKey: .duration)
        try container.encode(afterClipIndex, forKey: .afterClipIndex)
    }

    // MARK: - Computed Properties

    /// Effective duration of this transition (0 for cuts, duration for all others)
    var effectiveDuration: Double {
        type.requiresDuration ? duration : 0
    }

    /// Creates a copy of this transition with a new afterClipIndex
    func copy(withNewIndex newIndex: Int) -> ClipTransition {
        ClipTransition(
            id: UUID(),
            type: type,
            duration: duration,
            afterClipIndex: newIndex
        )
    }
}

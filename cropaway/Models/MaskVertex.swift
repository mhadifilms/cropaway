//
//  MaskVertex.swift
//  cropaway
//

import Foundation
import CoreGraphics

/// A vertex in a mask path that supports bezier curves
struct MaskVertex: Identifiable, Equatable, Codable {
    let id: UUID
    var position: CGPoint

    // Bezier control handles (relative to position, normalized)
    // nil means no curve, just a sharp corner
    var controlIn: CGPoint?   // Handle coming into this point
    var controlOut: CGPoint?  // Handle going out of this point

    init(position: CGPoint, controlIn: CGPoint? = nil, controlOut: CGPoint? = nil) {
        self.id = UUID()
        self.position = position
        self.controlIn = controlIn
        self.controlOut = controlOut
    }

    var hasCurve: Bool {
        controlIn != nil || controlOut != nil
    }

    // Get absolute position of control handles (in normalized coords)
    func absoluteControlIn() -> CGPoint? {
        guard let ctrl = controlIn else { return nil }
        return CGPoint(
            x: position.x + ctrl.x,
            y: position.y + ctrl.y
        )
    }

    func absoluteControlOut() -> CGPoint? {
        guard let ctrl = controlOut else { return nil }
        return CGPoint(
            x: position.x + ctrl.x,
            y: position.y + ctrl.y
        )
    }

    // Mirror control handles (for smooth curves)
    mutating func mirrorControlIn() {
        if let ctrl = controlOut {
            controlIn = CGPoint(x: -ctrl.x, y: -ctrl.y)
        }
    }

    mutating func mirrorControlOut() {
        if let ctrl = controlIn {
            controlOut = CGPoint(x: -ctrl.x, y: -ctrl.y)
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, positionX, positionY, controlInX, controlInY, controlOutX, controlOutY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let px = try container.decode(Double.self, forKey: .positionX)
        let py = try container.decode(Double.self, forKey: .positionY)
        position = CGPoint(x: px, y: py)

        if let cix = try container.decodeIfPresent(Double.self, forKey: .controlInX),
           let ciy = try container.decodeIfPresent(Double.self, forKey: .controlInY) {
            controlIn = CGPoint(x: cix, y: ciy)
        }

        if let cox = try container.decodeIfPresent(Double.self, forKey: .controlOutX),
           let coy = try container.decodeIfPresent(Double.self, forKey: .controlOutY) {
            controlOut = CGPoint(x: cox, y: coy)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(position.x, forKey: .positionX)
        try container.encode(position.y, forKey: .positionY)

        if let ci = controlIn {
            try container.encode(ci.x, forKey: .controlInX)
            try container.encode(ci.y, forKey: .controlInY)
        }

        if let co = controlOut {
            try container.encode(co.x, forKey: .controlOutX)
            try container.encode(co.y, forKey: .controlOutY)
        }
    }
}

/// Helper to convert between legacy [CGPoint] and [MaskVertex]
extension Array where Element == MaskVertex {
    /// Convert to simple point array (loses bezier data)
    func toPoints() -> [CGPoint] {
        map { $0.position }
    }

    /// Create from simple point array (no bezier data)
    static func fromPoints(_ points: [CGPoint]) -> [MaskVertex] {
        points.map { MaskVertex(position: $0) }
    }

    /// Convert to JSON-compatible format with full bezier data
    func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Create from JSON data with full bezier data
    static func fromJSON(_ data: Data) throws -> [MaskVertex] {
        try JSONDecoder().decode([MaskVertex].self, from: data)
    }
}

extension Array where Element == CGPoint {
    /// Convert to mask vertices (no bezier data)
    func toVertices() -> [MaskVertex] {
        map { MaskVertex(position: $0) }
    }
}

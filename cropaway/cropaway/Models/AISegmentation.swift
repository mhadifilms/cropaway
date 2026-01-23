//
//  AISegmentation.swift
//  cropaway
//

import Foundation
import CoreGraphics

/// A point prompt for AI segmentation (click to include/exclude)
struct AIPromptPoint: Codable, Identifiable, Equatable {
    let id: UUID
    var position: CGPoint      // Normalized 0-1 coordinates
    var isPositive: Bool       // true = include region, false = exclude region

    init(position: CGPoint, isPositive: Bool = true) {
        self.id = UUID()
        self.position = position
        self.isPositive = isPositive
    }

    /// SAM3 label: 1 for foreground (positive), 0 for background (negative)
    var label: Int {
        isPositive ? 1 : 0
    }
}

/// Result from SAM3 segmentation
struct AIMaskResult: Codable, Equatable {
    var maskData: Data         // RLE-encoded binary mask
    var boundingBox: CGRect    // Object bounding box (normalized 0-1)
    var confidence: Double     // Segmentation confidence score (0-1)
    var objectId: String       // Unique ID for tracking continuity

    init(maskData: Data, boundingBox: CGRect, confidence: Double, objectId: String = UUID().uuidString) {
        self.maskData = maskData
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.objectId = objectId
    }
}

/// Status of the SAM3 server
enum SAM3ServerStatus: Equatable {
    case stopped
    case starting
    case ready
    case processing
    case error(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Available SAM model sizes
enum SAM3ModelSize: String, CaseIterable, Identifiable {
    case base = "facebook/sam-vit-base"
    case large = "facebook/sam-vit-large"
    case huge = "facebook/sam-vit-huge"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .base: return "SAM Base"
        case .large: return "SAM Large"
        case .huge: return "SAM Huge"
        }
    }

    var description: String {
        switch self {
        case .base: return "Fastest inference, good for quick previews"
        case .large: return "Balanced speed and quality"
        case .huge: return "Best quality, slower inference"
        }
    }

    /// Approximate download size in bytes
    var downloadSize: Int64 {
        switch self {
        case .base: return 375_000_000   // ~375MB
        case .large: return 1_200_000_000 // ~1.2GB
        case .huge: return 2_500_000_000  // ~2.5GB
        }
    }
}

/// Direction for video tracking
enum TrackDirection {
    case forward
    case backward
}

// MARK: - RLE Mask Utilities

extension AIMaskResult {
    /// Decode RLE mask data to a bitmap
    static func decodeMask(_ data: Data, width: Int, height: Int) -> [UInt8]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let counts = json["counts"] as? [Int],
              let size = json["size"] as? [Int],
              size.count == 2 else {
            // Try raw bitmap fallback
            if data.count == width * height {
                return [UInt8](data)
            }
            return nil
        }

        let h = size[0]
        let w = size[1]
        var mask = [UInt8](repeating: 0, count: h * w)
        var idx = 0
        var value: UInt8 = 0

        for count in counts {
            for _ in 0..<count {
                if idx < mask.count {
                    mask[idx] = value
                    idx += 1
                }
            }
            value = value == 0 ? 255 : 0
        }

        return mask
    }

    /// Encode a bitmap to RLE format
    static func encodeMask(_ bitmap: [UInt8], width: Int, height: Int) -> Data? {
        var counts: [Int] = []
        var currentValue: UInt8 = 0
        var currentCount = 0

        for pixel in bitmap {
            let value: UInt8 = pixel > 127 ? 255 : 0
            if value == currentValue {
                currentCount += 1
            } else {
                if currentCount > 0 {
                    counts.append(currentCount)
                }
                currentValue = value
                currentCount = 1
            }
        }
        if currentCount > 0 {
            counts.append(currentCount)
        }

        let rle: [String: Any] = [
            "counts": counts,
            "size": [height, width]
        ]

        return try? JSONSerialization.data(withJSONObject: rle)
    }
}

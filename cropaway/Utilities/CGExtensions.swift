//
//  CGExtensions.swift
//  cropaway
//

import Foundation
import CoreGraphics

extension CGRect {
    // Convert from normalized (0-1) to pixel coordinates
    func denormalized(to size: CGSize) -> CGRect {
        CGRect(
            x: origin.x * size.width,
            y: origin.y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    // Convert from pixel coordinates to normalized (0-1)
    func normalized(to size: CGSize) -> CGRect {
        guard size.width > 0 && size.height > 0 else { return self }
        return CGRect(
            x: origin.x / size.width,
            y: origin.y / size.height,
            width: width / size.width,
            height: height / size.height
        )
    }

    // Clamp to valid normalized range
    func clamped() -> CGRect {
        var rect = self
        rect.origin.x = max(0, min(1, rect.origin.x))
        rect.origin.y = max(0, min(1, rect.origin.y))
        rect.size.width = max(0.01, min(1 - rect.origin.x, rect.size.width))
        rect.size.height = max(0.01, min(1 - rect.origin.y, rect.size.height))
        return rect
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    init(center: CGPoint, size: CGSize) {
        self.init(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

extension CGPoint {
    func denormalized(to size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    func normalized(to size: CGSize) -> CGPoint {
        guard size.width > 0 && size.height > 0 else { return self }
        return CGPoint(x: x / size.width, y: y / size.height)
    }

    func clamped() -> CGPoint {
        CGPoint(
            x: max(0, min(1, x)),
            y: max(0, min(1, y))
        )
    }

    func distance(to other: CGPoint) -> CGFloat {
        sqrt(pow(other.x - x, 2) + pow(other.y - y, 2))
    }
}

extension CGSize {
    var aspectRatio: CGFloat {
        guard height > 0 else { return 1 }
        return width / height
    }

    var isValid: Bool {
        width > 0 && height > 0 && width.isFinite && height.isFinite
    }

    func fitting(in container: CGSize) -> CGSize {
        guard width > 0 && height > 0 && container.width > 0 && container.height > 0 else {
            return container
        }
        let widthRatio = container.width / width
        let heightRatio = container.height / height
        let scale = min(widthRatio, heightRatio)
        return CGSize(width: width * scale, height: height * scale)
    }
}

// Linear interpolation helpers
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    CGPoint(
        x: lerp(a.x, b.x, CGFloat(t)),
        y: lerp(a.y, b.y, CGFloat(t))
    )
}

func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
    CGRect(
        x: lerp(a.origin.x, b.origin.x, CGFloat(t)),
        y: lerp(a.origin.y, b.origin.y, CGFloat(t)),
        width: lerp(a.width, b.width, CGFloat(t)),
        height: lerp(a.height, b.height, CGFloat(t))
    )
}

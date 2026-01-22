//
//  KeyframeInterpolator.swift
//  cropaway
//

import Foundation
import CoreGraphics

struct InterpolatedCropState {
    var cropRect: CGRect
    var edgeInsets: EdgeInsets
    var circleCenter: CGPoint
    var circleRadius: Double
    var freehandPoints: [CGPoint]
}

final class KeyframeInterpolator {
    static let shared = KeyframeInterpolator()

    private init() {}

    func interpolate(
        keyframes: [Keyframe],
        at timestamp: Double,
        mode: CropMode
    ) -> InterpolatedCropState {
        guard !keyframes.isEmpty else {
            return defaultState()
        }

        let sorted = keyframes.sorted { $0.timestamp < $1.timestamp }

        // Before first keyframe
        if timestamp <= sorted.first!.timestamp {
            return stateFromKeyframe(sorted.first!)
        }

        // After last keyframe
        if timestamp >= sorted.last!.timestamp {
            return stateFromKeyframe(sorted.last!)
        }

        // Find surrounding keyframes
        guard let nextIndex = sorted.firstIndex(where: { $0.timestamp > timestamp }) else {
            return stateFromKeyframe(sorted.last!)
        }

        let prev = sorted[nextIndex - 1]
        let next = sorted[nextIndex]

        // Calculate interpolation factor
        let duration = next.timestamp - prev.timestamp
        guard duration > 0 else {
            return stateFromKeyframe(prev)
        }

        let elapsed = timestamp - prev.timestamp
        let rawT = elapsed / duration

        // Apply easing based on previous keyframe's interpolation
        let t = applyEasing(rawT, interpolation: prev.interpolation)

        // Interpolate
        return interpolateStates(
            from: stateFromKeyframe(prev),
            to: stateFromKeyframe(next),
            t: t
        )
    }

    private func defaultState() -> InterpolatedCropState {
        InterpolatedCropState(
            cropRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            edgeInsets: EdgeInsets(),
            circleCenter: CGPoint(x: 0.5, y: 0.5),
            circleRadius: 0.4,
            freehandPoints: []
        )
    }

    private func stateFromKeyframe(_ keyframe: Keyframe) -> InterpolatedCropState {
        InterpolatedCropState(
            cropRect: keyframe.cropRect,
            edgeInsets: keyframe.edgeInsets,
            circleCenter: keyframe.circleCenter,
            circleRadius: keyframe.circleRadius,
            freehandPoints: [] // Freehand not interpolated
        )
    }

    private func applyEasing(_ t: Double, interpolation: KeyframeInterpolation) -> Double {
        switch interpolation {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .hold:
            return 0 // Always use start value
        }
    }

    private func interpolateStates(
        from: InterpolatedCropState,
        to: InterpolatedCropState,
        t: Double
    ) -> InterpolatedCropState {
        InterpolatedCropState(
            cropRect: lerp(from.cropRect, to.cropRect, t),
            edgeInsets: interpolateEdgeInsets(from.edgeInsets, to.edgeInsets, t),
            circleCenter: lerp(from.circleCenter, to.circleCenter, t),
            circleRadius: lerp(from.circleRadius, to.circleRadius, t),
            freehandPoints: t < 0.5 ? from.freehandPoints : to.freehandPoints
        )
    }

    private func interpolateEdgeInsets(_ from: EdgeInsets, _ to: EdgeInsets, _ t: Double) -> EdgeInsets {
        EdgeInsets(
            top: lerp(from.top, to.top, t),
            left: lerp(from.left, to.left, t),
            bottom: lerp(from.bottom, to.bottom, t),
            right: lerp(from.right, to.right, t)
        )
    }
}

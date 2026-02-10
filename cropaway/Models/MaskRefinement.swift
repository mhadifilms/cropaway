//
//  MaskRefinement.swift
//  cropaway
//

import Foundation
import Combine

enum MorphMode: String, CaseIterable, Codable, Identifiable {
    case grow
    case shrink
    case open
    case close

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grow: return "Grow"
        case .shrink: return "Shrink"
        case .open: return "Open"
        case .close: return "Close"
        }
    }
}

enum KernelShape: String, CaseIterable, Codable, Identifiable {
    case circle
    case diamond
    case square

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .circle: return "Circle"
        case .diamond: return "Diamond"
        case .square: return "Square"
        }
    }
}

enum Quality: String, CaseIterable, Codable, Identifiable {
    case faster
    case better

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .faster: return "Faster"
        case .better: return "Better"
        }
    }
}

struct MaskRefinementParams: Codable, Equatable {
    var mode: MorphMode = .grow
    var shape: KernelShape = .circle
    var radius: Int = 0
    var iterations: Int = 1
    var smoothing: Double = 0.0
    var denoise: Double = 0.0
    var blurRadius: Double = 0.0
    var inOutRatio: Double = 0.0
    var cleanBlack: Double = 0.0
    var cleanWhite: Double = 0.0
    var blackClip: Double = 0.0
    var whiteClip: Double = 100.0
    var postFilter: Double = 0.0
    var quality: Quality = .faster
    var smartRefine: Double = 0.0

    static let `default` = MaskRefinementParams()

    var isNeutral: Bool {
        self == .default
    }

    mutating func sanitize() {
        radius = radius.clamped(to: 0...100)
        iterations = iterations.clamped(to: 1...50)
        smoothing = smoothing.clamped(to: 0...20)
        denoise = denoise.clamped(to: 0...100)
        blurRadius = blurRadius.clamped(to: 0...200)
        inOutRatio = inOutRatio.clamped(to: -1...1)
        cleanBlack = cleanBlack.clamped(to: 0...50)
        cleanWhite = cleanWhite.clamped(to: 0...50)
        blackClip = blackClip.clamped(to: 0...100)
        whiteClip = whiteClip.clamped(to: 0...100)
        if whiteClip < blackClip + 0.5 {
            whiteClip = min(100, blackClip + 0.5)
        }
        postFilter = postFilter.clamped(to: 0...50)
        smartRefine = smartRefine.clamped(to: 0...100)
    }

    static func interpolated(from: MaskRefinementParams, to: MaskRefinementParams, t: Double) -> MaskRefinementParams {
        let clampedT = t.clamped(to: 0...1)

        var result = MaskRefinementParams(
            mode: clampedT < 0.5 ? from.mode : to.mode,
            shape: clampedT < 0.5 ? from.shape : to.shape,
            radius: Int((Double(from.radius) + (Double(to.radius) - Double(from.radius)) * clampedT).rounded()),
            iterations: Int((Double(from.iterations) + (Double(to.iterations) - Double(from.iterations)) * clampedT).rounded()),
            smoothing: from.smoothing + (to.smoothing - from.smoothing) * clampedT,
            denoise: from.denoise + (to.denoise - from.denoise) * clampedT,
            blurRadius: from.blurRadius + (to.blurRadius - from.blurRadius) * clampedT,
            inOutRatio: from.inOutRatio + (to.inOutRatio - from.inOutRatio) * clampedT,
            cleanBlack: from.cleanBlack + (to.cleanBlack - from.cleanBlack) * clampedT,
            cleanWhite: from.cleanWhite + (to.cleanWhite - from.cleanWhite) * clampedT,
            blackClip: from.blackClip + (to.blackClip - from.blackClip) * clampedT,
            whiteClip: from.whiteClip + (to.whiteClip - from.whiteClip) * clampedT,
            postFilter: from.postFilter + (to.postFilter - from.postFilter) * clampedT,
            quality: clampedT < 0.5 ? from.quality : to.quality,
            smartRefine: from.smartRefine + (to.smartRefine - from.smartRefine) * clampedT
        )
        result.sanitize()
        return result
    }

    static func automated(for mode: CropMode) -> MaskRefinementParams {
        switch mode {
        case .ai:
            return MaskRefinementParams(
                mode: .close,
                shape: .circle,
                radius: 2,
                iterations: 1,
                smoothing: 1.8,
                denoise: 22,
                blurRadius: 1.4,
                inOutRatio: 0.08,
                cleanBlack: 4,
                cleanWhite: 4,
                blackClip: 0,
                whiteClip: 100,
                postFilter: 0.4,
                quality: .better,
                smartRefine: 40
            )
        case .freehand:
            return MaskRefinementParams(
                mode: .grow,
                shape: .circle,
                radius: 1,
                iterations: 1,
                smoothing: 1.2,
                denoise: 8,
                blurRadius: 0.8,
                inOutRatio: 0,
                cleanBlack: 1,
                cleanWhite: 1,
                blackClip: 0,
                whiteClip: 100,
                postFilter: 0,
                quality: .faster,
                smartRefine: 0
            )
        case .circle, .rectangle:
            return MaskRefinementParams(
                mode: .grow,
                shape: .circle,
                radius: 0,
                iterations: 1,
                smoothing: 0.6,
                denoise: 0,
                blurRadius: 1.0,
                inOutRatio: 0,
                cleanBlack: 0,
                cleanWhite: 0,
                blackClip: 0,
                whiteClip: 100,
                postFilter: 0,
                quality: .faster,
                smartRefine: 0
            )
        }
    }
}

struct MaskRefinementPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var params: MaskRefinementParams
    var createdAt: Date

    init(id: UUID = UUID(), name: String, params: MaskRefinementParams, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.params = params
        self.createdAt = createdAt
    }
}

final class MaskRefinementPresetStore: ObservableObject {
    static let shared = MaskRefinementPresetStore()

    @Published private(set) var presets: [MaskRefinementPreset] = []

    private let defaults = UserDefaults.standard
    private let key = "MaskRefinementPresets"

    private init() {
        load()
    }

    func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([MaskRefinementPreset].self, from: data) else {
            presets = []
            return
        }
        presets = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    func savePreset(name: String, params: MaskRefinementParams) {
        var sanitized = params
        sanitized.sanitize()

        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            presets[index].params = sanitized
            persist()
            return
        }

        presets.insert(MaskRefinementPreset(name: name, params: sanitized), at: 0)
        persist()
    }

    func deletePreset(_ preset: MaskRefinementPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: key)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

//
//  CropEditorViewModel.swift
//  cropaway
//

import Combine
import Foundation
import SwiftUI
import CoreGraphics

@MainActor
final class CropEditorViewModel: ObservableObject {
    @Published var mode: CropMode = .rectangle
    @Published var isEditing: Bool = true
    @Published var isDragging: Bool = false  // True while user is actively dragging a handle

    // Rectangle crop (normalized 0-1)
    @Published var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    // Edge crop
    @Published var edgeInsets: EdgeInsets = EdgeInsets()

    // Circle crop
    @Published var circleCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var circleRadius: Double = 0.4

    // Freehand
    @Published var freehandPoints: [CGPoint] = []
    @Published var freehandPathData: Data? = nil  // Full bezier vertex data
    @Published var isDrawing: Bool = false

    // AI mask (fal.ai)
    @Published var aiMaskData: Data?
    @Published var aiPromptPoints: [AIPromptPoint] = []
    @Published var aiTextPrompt: String?
    @Published var aiBoundingBox: CGRect = .zero
    @Published var aiInteractionMode: AIInteractionMode = .point

    // Callback for when crop editing ends (drag gesture completed)
    // Used for auto-keyframe creation
    var onCropEditEnded: (() -> Void)?

    // Active video
    private var currentVideo: VideoItem?
    private var cancellables = Set<AnyCancellable>()

    func bind(to video: VideoItem) {
        cancellables.removeAll()
        currentVideo = video

        let config = video.cropConfiguration

        // Sync from config
        mode = config.mode
        cropRect = config.cropRect
        edgeInsets = config.edgeInsets
        circleCenter = config.circleCenter
        circleRadius = config.circleRadius
        freehandPoints = config.freehandPoints
        freehandPathData = config.freehandPathData
        aiMaskData = config.aiMaskData
        aiPromptPoints = config.aiPromptPoints
        aiTextPrompt = config.aiTextPrompt
        aiBoundingBox = config.aiBoundingBox
        aiInteractionMode = config.aiInteractionMode

        // Sync changes back to config
        $mode
            .dropFirst()
            .sink { config.mode = $0 }
            .store(in: &cancellables)

        $cropRect
            .dropFirst()
            .sink { config.cropRect = $0 }
            .store(in: &cancellables)

        $edgeInsets
            .dropFirst()
            .sink { config.edgeInsets = $0 }
            .store(in: &cancellables)

        $circleCenter
            .dropFirst()
            .sink { config.circleCenter = $0 }
            .store(in: &cancellables)

        $circleRadius
            .dropFirst()
            .sink { config.circleRadius = $0 }
            .store(in: &cancellables)

        $freehandPoints
            .dropFirst()
            .sink { config.freehandPoints = $0 }
            .store(in: &cancellables)

        $freehandPathData
            .dropFirst()
            .sink { config.freehandPathData = $0 }
            .store(in: &cancellables)

        $aiMaskData
            .dropFirst()
            .sink { config.aiMaskData = $0 }
            .store(in: &cancellables)

        $aiPromptPoints
            .dropFirst()
            .sink { config.aiPromptPoints = $0 }
            .store(in: &cancellables)

        $aiTextPrompt
            .dropFirst()
            .sink { config.aiTextPrompt = $0 }
            .store(in: &cancellables)

        $aiBoundingBox
            .dropFirst()
            .sink { config.aiBoundingBox = $0 }
            .store(in: &cancellables)

        $aiInteractionMode
            .dropFirst()
            .sink { config.aiInteractionMode = $0 }
            .store(in: &cancellables)
    }

    // Get effective crop area for current mode
    var effectiveCropRect: CGRect {
        switch mode {
        case .rectangle:
            return cropRect
        case .circle:
            let diameter = circleRadius * 2
            return CGRect(
                x: circleCenter.x - circleRadius,
                y: circleCenter.y - circleRadius,
                width: diameter,
                height: diameter
            )
        case .freehand:
            guard !freehandPoints.isEmpty else { return cropRect }
            let xs = freehandPoints.map { $0.x }
            let ys = freehandPoints.map { $0.y }
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 1
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 1
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .ai:
            return aiBoundingBox.width > 0 ? aiBoundingBox : CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    func reset() {
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        edgeInsets = EdgeInsets()
        circleCenter = CGPoint(x: 0.5, y: 0.5)
        circleRadius = 0.4
        freehandPoints = []
        freehandPathData = nil
        aiMaskData = nil
        aiPromptPoints = []
        aiTextPrompt = nil
        aiBoundingBox = .zero
    }

    // Freehand drawing
    func startDrawing(at point: CGPoint) {
        freehandPoints = [point]
        isDrawing = true
    }

    func continueDrawing(to point: CGPoint) {
        guard isDrawing else { return }
        freehandPoints.append(point)
    }

    func endDrawing() {
        isDrawing = false
        // Close the path by adding start point if needed
        if let first = freehandPoints.first, let last = freehandPoints.last {
            if first.distance(to: last) > 0.01 {
                freehandPoints.append(first)
            }
        }
    }

    func clearFreehand() {
        freehandPoints = []
        freehandPathData = nil
    }

    /// Called when a crop editing gesture ends (drag completed)
    /// This triggers the onCropEditEnded callback for auto-keyframe creation
    func notifyCropEditEnded() {
        onCropEditEnded?()
    }

    // MARK: - AI Segmentation

    /// Clear AI mask data
    func clearAIMask() {
        aiMaskData = nil
        aiPromptPoints = []
        aiTextPrompt = nil
        aiBoundingBox = .zero
    }
}

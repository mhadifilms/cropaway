//
//  VideoDetailView.swift
//  cropaway
//

import SwiftUI
import AVKit

struct VideoDetailView: View {
    @ObservedObject var video: VideoItem
    @Binding var viewScale: CGFloat

    @Environment(VideoPlayerViewModel.self) private var playerVM: VideoPlayerViewModel
    @Environment(CropEditorViewModel.self) private var cropEditorVM: CropEditorViewModel
    @Environment(ExportViewModel.self) private var exportVM: ExportViewModel
    @Environment(KeyframeViewModel.self) private var keyframeVM: KeyframeViewModel
    @Environment(TimelineViewModel.self) private var timelineVM: TimelineViewModel

    // If timeline has a selected clip, use that; otherwise use the passed video
    private var activeVideo: VideoItem {
        if let clip = timelineVM.selectedClip, let clipVideo = clip.videoItem {
            return clipVideo
        }
        return video
    }
    
    // Read from active video's crop config
    private var preserveSize: Bool { activeVideo.cropConfiguration.preserveWidth }
    private var enableAlpha: Bool { activeVideo.cropConfiguration.enableAlphaChannel }

    var body: some View {
        VStack(spacing: 0) {
            CropToolbarView(video: activeVideo)

            GeometryReader { _ in
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // Video with live crop preview
                        LiveCropPreviewView(
                            preserveSize: preserveSize,
                            enableAlpha: enableAlpha,
                            viewScale: $viewScale
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if enableAlpha {
                                // True transparency - app background shows through masked areas
                                Color.clear
                            } else {
                                Color.black
                            }
                        }
                        .clipped()

                        // Player controls
                        VideoPlayerControlsView()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .toolbarGlassBackground()

                        // Keyframe timeline (when enabled)
                        if keyframeVM.keyframesEnabled {
                            Divider()
                            KeyframeTimelineView()
                                .frame(height: 56)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .toolbarGlassBackground()
                        }

                        // Sequence timeline (when panel is visible)
                        if timelineVM.isTimelinePanelVisible && timelineVM.activeTimeline != nil {
                            Divider()
                            TimelineTrackView()
                                .frame(height: 80)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .toolbarGlassBackground()
                        }
                    }

                    Divider()

                    MaskRefinementPanelView(video: activeVideo)
                        .frame(width: 320)
                        .background(.bar)
                }
            }
        }
    }
}

struct LiveCropPreviewView: View {
    let preserveSize: Bool
    let enableAlpha: Bool
    @Binding var viewScale: CGFloat

    @Environment(VideoPlayerViewModel.self) private var playerVM: VideoPlayerViewModel
    @Environment(CropEditorViewModel.self) private var cropEditorVM: CropEditorViewModel

    // For pinch-to-zoom gesture
    @GestureState private var magnifyBy: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size

            if playerVM.videoSize.isValid {
                let videoSize = playerVM.videoSize
                let cropRect = cropEditorVM.effectiveCropRect

                // Calculate display sizes
                let displayConfig = calculateDisplayConfig(
                    videoSize: videoSize,
                    cropRect: cropRect,
                    containerSize: containerSize,
                    preserveSize: preserveSize
                )

                ZStack {
                    // Background: transparent for alpha mode, black otherwise
                    if !enableAlpha {
                        Color.black
                            .frame(width: displayConfig.frameSize.width, height: displayConfig.frameSize.height)
                    }

                    // Video layer - behavior depends on preserveSize and enableAlpha
                    if !preserveSize {
                        // Preserve Size OFF: Show only cropped area filling the frame
                        // Use ClippedVideoPlayerView which uses AVPlayerLayer with proper CALayer clipping
                        let _ = print("[VideoDetailView] preserveSize=OFF, cropRect=\(cropRect), frameSize=\(displayConfig.frameSize), frameAspect=\(displayConfig.frameSize.width/displayConfig.frameSize.height)")
                        ClippedVideoPlayerView(
                            cropRect: cropRect,
                            frameSize: displayConfig.frameSize
                        )
                        .frame(width: displayConfig.frameSize.width, height: displayConfig.frameSize.height)
                    } else if enableAlpha {
                        // Preserve Size ON + Alpha ON: Show full video with mask (transparency outside crop)
                        MaskedVideoPlayerView(
                            maskMode: cropEditorVM.mode,
                            cropRect: cropRect,
                            circleCenter: cropEditorVM.circleCenter,
                            circleRadius: cropEditorVM.circleRadius,
                            freehandPoints: cropEditorVM.freehandPoints,
                            freehandPathData: cropEditorVM.freehandPathData,
                            aiMaskData: cropEditorVM.aiMaskData,
                            videoDisplaySize: displayConfig.videoDisplaySize,
                            maskRefinement: cropEditorVM.showRefinedMaskPreview ? cropEditorVM.maskRefinement : .default
                        )
                        .frame(width: displayConfig.videoDisplaySize.width, height: displayConfig.videoDisplaySize.height)
                        .offset(x: displayConfig.videoOffset.width, y: displayConfig.videoOffset.height)
                    } else {
                        // Preserve Size ON + Alpha OFF: Show full video with dimmed overlay outside crop
                        ZStack {
                            VideoPlayerView()
                                .frame(width: displayConfig.videoDisplaySize.width, height: displayConfig.videoDisplaySize.height)

                            // Dimmed overlay outside crop area
                            DimmedCropOverlay(
                                mode: cropEditorVM.mode,
                                cropRect: cropRect,
                                circleCenter: cropEditorVM.circleCenter,
                                circleRadius: cropEditorVM.circleRadius,
                                freehandPoints: cropEditorVM.freehandPoints,
                                freehandPathData: cropEditorVM.freehandPathData,
                                aiMaskData: cropEditorVM.aiMaskData,
                                videoSize: displayConfig.videoDisplaySize,
                                maskRefinement: cropEditorVM.showRefinedMaskPreview ? cropEditorVM.maskRefinement : .default
                            )
                        }
                        .offset(x: displayConfig.videoOffset.width, y: displayConfig.videoOffset.height)
                    }

                    // Crop handles overlay - only show when preserveSize is ON
                    // When preserveSize is OFF, the cropped view fills the frame and handles would be confusing
                    if preserveSize {
                        CropHandlesView(videoDisplaySize: displayConfig.videoDisplaySize)
                            .offset(x: displayConfig.videoOffset.width, y: displayConfig.videoOffset.height)
                    }
                }
                .frame(width: displayConfig.frameSize.width, height: displayConfig.frameSize.height)
                .clipped()  // Clip to frame bounds (important for preserveSize OFF)
                // Force view recreation when switching modes to avoid stale state
                .id("preview-\(preserveSize)-\(enableAlpha)-\(cropEditorVM.mode)-\(cropEditorVM.aiMaskData?.count ?? 0)")
                .scaleEffect(viewScale * magnifyBy)
                .position(x: containerSize.width / 2, y: containerSize.height / 2)
                .gesture(magnifyGesture)
            } else {
                // Loading state
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($magnifyBy) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let newScale = viewScale * value.magnification
                viewScale = max(0.5, min(3.0, newScale))
            }
    }

    struct DisplayConfig {
        var frameSize: CGSize
        var videoDisplaySize: CGSize
        var videoOffset: CGSize
    }

    func calculateDisplayConfig(
        videoSize: CGSize,
        cropRect: CGRect,
        containerSize: CGSize,
        preserveSize: Bool
    ) -> DisplayConfig {
        if preserveSize {
            // Show full video size, fit to container
            let fittedSize = videoSize.fitting(in: containerSize)
            return DisplayConfig(
                frameSize: fittedSize,
                videoDisplaySize: fittedSize,
                videoOffset: .zero
            )
        } else {
            // Show only cropped region, zoomed to fill container
            // Calculate the pixel dimensions of the crop region
            let croppedPixelSize = CGSize(
                width: videoSize.width * cropRect.width,
                height: videoSize.height * cropRect.height
            )
            // Fit the crop region to the container (maintains crop aspect ratio)
            let fittedCroppedSize = croppedPixelSize.fitting(in: containerSize)

            // For the handles overlay, calculate the full video display size
            // This allows handles to be positioned correctly when editing while zoomed
            let scale = fittedCroppedSize.width / croppedPixelSize.width
            let fullVideoDisplaySize = CGSize(
                width: videoSize.width * scale,
                height: videoSize.height * scale
            )

            // Offset to position handles correctly (crop center at frame center)
            let offsetX = -(cropRect.midX - 0.5) * fullVideoDisplaySize.width
            let offsetY = -(cropRect.midY - 0.5) * fullVideoDisplaySize.height

            return DisplayConfig(
                frameSize: fittedCroppedSize,
                videoDisplaySize: fullVideoDisplaySize,
                videoOffset: CGSize(width: offsetX, height: offsetY)
            )
        }
    }
}

/// View that renders crop mask for all modes including AI RLE masks
struct CropMaskView: View {
    let mode: CropMode
    let cropRect: CGRect
    let circleCenter: CGPoint
    let circleRadius: Double
    let freehandPoints: [CGPoint]
    var freehandPathData: Data? = nil
    var aiMaskData: Data? = nil
    let size: CGSize

    var body: some View {
        if mode == .ai {
            // AI mode: render RLE mask as image, or show full video if no mask yet
            if let maskData = aiMaskData {
                AIMaskImageView(maskData: maskData, size: size)
            } else {
                // No mask data yet - show full video (white mask = everything visible)
                Color.white
                    .frame(width: size.width, height: size.height)
            }
        } else {
            // Other modes: use shape-based mask
            // White fill = visible area, outside = transparent
            CropMaskShape(
                mode: mode,
                cropRect: cropRect,
                circleCenter: circleCenter,
                circleRadius: circleRadius,
                freehandPoints: freehandPoints,
                freehandPathData: freehandPathData
            )
            .fill(Color.white)
            .frame(width: size.width, height: size.height)
        }
    }
}

/// Renders RLE mask data as an image for use as SwiftUI mask
/// Uses luminanceToAlpha to convert grayscale mask values to alpha channel
struct AIMaskImageView: View {
    let maskData: Data
    let size: CGSize

    var body: some View {
        if let (cgImage, _, _) = AIMaskResult.decodeMaskToImage(maskData) {
            Image(decorative: cgImage, scale: 1.0)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .luminanceToAlpha()  // Convert grayscale to alpha for proper masking
        } else {
            // Mask decode failed - show nothing (empty mask)
            Color.clear
                .frame(width: size.width, height: size.height)
        }
    }
}

struct CropMaskShape: Shape {
    let mode: CropMode
    let cropRect: CGRect
    let circleCenter: CGPoint
    let circleRadius: Double
    let freehandPoints: [CGPoint]
    var freehandPathData: Data? = nil

    func path(in rect: CGRect) -> Path {
        switch mode {
        case .rectangle:
            let pixelRect = cropRect.denormalized(to: rect.size)
            return Path(pixelRect)

        case .circle:
            let center = circleCenter.denormalized(to: rect.size)
            let radius = circleRadius * min(rect.width, rect.height)
            return Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))

        case .freehand:
            // Try to use bezier path data if available
            if let data = freehandPathData,
               let vertices = try? JSONDecoder().decode([MaskVertex].self, from: data),
               vertices.count >= 3 {
                return buildBezierPath(vertices: vertices, size: rect.size)
            }
            // Fallback to simple points
            guard freehandPoints.count >= 3 else {
                return Path(rect)
            }
            var path = Path()
            let first = freehandPoints[0].denormalized(to: rect.size)
            path.move(to: first)
            for point in freehandPoints.dropFirst() {
                path.addLine(to: point.denormalized(to: rect.size))
            }
            path.closeSubpath()
            return path

        case .ai:
            // AI mode handled by CropMaskView with AIMaskImageView
            // Return empty path if this is ever called (no mask = nothing visible)
            return Path()
        }
    }

    /// Build a SwiftUI Path with bezier curves from MaskVertex array
    private func buildBezierPath(vertices: [MaskVertex], size: CGSize) -> Path {
        Path { path in
            guard vertices.count >= 3 else { return }

            path.move(to: vertices[0].position.denormalized(to: size))

            for i in 1..<vertices.count {
                addBezierSegment(to: &path, from: vertices[i-1], to: vertices[i], size: size)
            }

            // Close the path
            addBezierSegment(to: &path, from: vertices[vertices.count - 1], to: vertices[0], size: size)
            path.closeSubpath()
        }
    }

    /// Add a bezier curve segment between two vertices
    private func addBezierSegment(to path: inout Path, from: MaskVertex, to: MaskVertex, size: CGSize) {
        let fromPx = from.position.denormalized(to: size)
        let toPx = to.position.denormalized(to: size)

        let hasFromHandle = from.controlOut != nil
        let hasToHandle = to.controlIn != nil

        if hasFromHandle && hasToHandle {
            let ctrl1 = CGPoint(
                x: fromPx.x + from.controlOut!.x * size.width,
                y: fromPx.y + from.controlOut!.y * size.height
            )
            let ctrl2 = CGPoint(
                x: toPx.x + to.controlIn!.x * size.width,
                y: toPx.y + to.controlIn!.y * size.height
            )
            path.addCurve(to: toPx, control1: ctrl1, control2: ctrl2)
        } else if hasFromHandle {
            let ctrl = CGPoint(
                x: fromPx.x + from.controlOut!.x * size.width,
                y: fromPx.y + from.controlOut!.y * size.height
            )
            path.addQuadCurve(to: toPx, control: ctrl)
        } else if hasToHandle {
            let ctrl = CGPoint(
                x: toPx.x + to.controlIn!.x * size.width,
                y: toPx.y + to.controlIn!.y * size.height
            )
            path.addQuadCurve(to: toPx, control: ctrl)
        } else {
            path.addLine(to: toPx)
        }
    }
}

/// Dimmed overlay that darkens areas OUTSIDE the crop region
/// Used when alpha channel is NOT enabled to show video is still there but dimmed
struct DimmedCropOverlay: View {
    let mode: CropMode
    let cropRect: CGRect
    let circleCenter: CGPoint
    let circleRadius: Double
    let freehandPoints: [CGPoint]
    var freehandPathData: Data? = nil
    var aiMaskData: Data? = nil
    let videoSize: CGSize
    var maskRefinement: MaskRefinementParams = .default

    private static let renderer = CropMaskRenderer()

    var body: some View {
        let state = InterpolatedCropState(
            cropRect: cropRect,
            edgeInsets: .init(),
            circleCenter: circleCenter,
            circleRadius: circleRadius,
            freehandPoints: freehandPoints,
            freehandPathData: freehandPathData,
            aiMaskData: aiMaskData,
            aiBoundingBox: .zero,
            maskRefinement: maskRefinement
        )
        let maskImage = Self.renderer.renderMaskImage(
            mode: mode,
            state: state,
            size: videoSize,
            refinement: maskRefinement,
            guideImage: nil
        )

        ZStack {
            Color.black.opacity(0.5)

            if let maskImage {
                Image(decorative: maskImage, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .frame(width: videoSize.width, height: videoSize.height)
        .allowsHitTesting(false)
    }
}

/// Dimmed overlay for AI mode using RLE mask
struct AIDimmedMaskView: View {
    let maskData: Data
    let size: CGSize

    var body: some View {
        let _ = print("[AIDimmedMaskView] Rendering with \(maskData.count) bytes, size: \(size)")

        // Decode mask once for the view
        let decoded = AIMaskResult.decodeMaskToImage(maskData)

        ZStack {
            // Always show dim overlay
            Color.black.opacity(0.5)

            // If mask decoded successfully, cut it out
            if let (cgImage, w, h) = decoded {
                let _ = print("[AIDimmedMaskView] Mask decoded: \(w)x\(h)")
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .blendMode(.destinationOut)
            } else {
                // Show red overlay to indicate decode failure
                let _ = print("[AIDimmedMaskView] FAILED to decode mask - showing red indicator")
                Color.red.opacity(0.3)
            }
        }
        .compositingGroup()
        .frame(width: size.width, height: size.height)
    }
}

struct CropHandlesView: View {
    let videoDisplaySize: CGSize

    @Environment(CropEditorViewModel.self) private var cropEditorVM: CropEditorViewModel

    var body: some View {
        if videoDisplaySize.isValid {
            ZStack {
                @Bindable var cropEditor = cropEditorVM
                
                switch cropEditor.mode {
                case .rectangle:
                    RectangleCropView(
                        rect: $cropEditor.cropRect,
                        videoSize: videoDisplaySize
                    )
                case .circle:
                    CircleCropView(
                        center: $cropEditor.circleCenter,
                        radius: $cropEditor.circleRadius,
                        videoSize: videoDisplaySize
                    )
                case .freehand:
                    FreehandMaskView(
                        points: $cropEditor.freehandPoints,
                        isDrawing: $cropEditor.isDrawing,
                        pathData: $cropEditor.freehandPathData,
                        videoSize: videoDisplaySize,
                        onEditEnded: cropEditor.notifyCropEditEnded
                    )
                case .ai:
                    AIEditorView(
                        promptPoints: $cropEditor.aiPromptPoints,
                        maskData: $cropEditor.aiMaskData,
                        boundingBox: $cropEditor.aiBoundingBox,
                        interactionMode: $cropEditor.aiInteractionMode,
                        videoSize: videoDisplaySize,
                        onEditEnded: cropEditor.notifyCropEditEnded
                    )
                }
            }
            .frame(width: videoDisplaySize.width, height: videoDisplaySize.height)
        }
    }
}

/// Background for alpha preview - true transparency so app background shows through
struct AlphaPreviewBackground: View {
    var body: some View {
        Color.clear
    }
}

/// NSVisualEffectView wrapper for older macOS
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct CheckerboardView: View {
    let squareSize: CGFloat = 10
    var opacity: Double = 1.0

    var body: some View {
        Canvas { context, size in
            let rows = Int(ceil(size.height / squareSize))
            let cols = Int(ceil(size.width / squareSize))

            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? Color(white: 0.4).opacity(opacity) : Color(white: 0.3).opacity(opacity))
                    )
                }
            }
        }
    }
}

#Preview {
    let video = VideoItem(sourceURL: URL(fileURLWithPath: "/test.mov"))
    VideoDetailView(video: video, viewScale: .constant(1.0))
        .environment(VideoPlayerViewModel())
        .environment(CropEditorViewModel())
        .environment(ExportViewModel())
        .environment(KeyframeViewModel())
        .frame(width: 800, height: 600)
}

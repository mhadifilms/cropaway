//
//  MainContentView.swift
//  cropaway
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

struct MainContentView: View {
    @EnvironmentObject var projectVM: ProjectViewModel
    @StateObject private var playerVM = VideoPlayerViewModel()
    @StateObject private var cropEditorVM = CropEditorViewModel()
    @StateObject private var exportVM = ExportViewModel()
    @StateObject private var keyframeVM = KeyframeViewModel()
    @StateObject private var undoManager = CropUndoManager()

    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var viewScale: CGFloat = 1.0
    @State private var copiedCropSettings: CopiedCropSettings?
    @State private var isPreviewMode: Bool = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VideoSidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .onDrop(of: [.fileURL], isTargeted: nil) { handleDrop($0) }
        .onChange(of: projectVM.selectedVideo) { handleVideoChange($0, $1) }
        .onChange(of: playerVM.currentTime) { handleTimeChange($0, $1) }
        .sheet(isPresented: showExportSheet) { exportSheet }
        .alert("Export Error", isPresented: errorBinding) { errorAlert }
        .modifier(FileNotificationHandler(projectVM: projectVM, exportVM: exportVM, playerVM: playerVM))
        .modifier(EditNotificationHandler(undoManager: undoManager, cropEditorVM: cropEditorVM, copiedSettings: $copiedCropSettings))
        .modifier(ViewNotificationHandler(viewScale: $viewScale, columnVisibility: $columnVisibility, keyframeVM: keyframeVM, isPreviewMode: $isPreviewMode))
        .modifier(CropNotificationHandler(undoManager: undoManager, cropEditorVM: cropEditorVM, keyframeVM: keyframeVM, playerVM: playerVM))
        .modifier(PlaybackNotificationHandler(playerVM: playerVM))
        .modifier(VideoSelectionNotificationHandler(projectVM: projectVM))
    }

    @ViewBuilder
    private var detailContent: some View {
        if let video = projectVM.selectedVideo {
            VideoDetailView(video: video, viewScale: $viewScale)
                .environmentObject(playerVM)
                .environmentObject(cropEditorVM)
                .environmentObject(exportVM)
                .environmentObject(keyframeVM)
                .environmentObject(undoManager)
        } else {
            EmptyStateView()
        }
    }

    @ViewBuilder
    private var exportSheet: some View {
        ExportProgressView()
            .environmentObject(exportVM)
    }

    private var showExportSheet: Binding<Bool> {
        Binding(
            get: { exportVM.isExporting || !exportVM.exportedURLs.isEmpty },
            set: { if !$0 { exportVM.exportedURLs = [] } }
        )
    }

    private var errorBinding: Binding<Bool> {
        .constant(exportVM.error != nil)
    }

    @ViewBuilder
    private var errorAlert: some View {
        Button("OK") { exportVM.error = nil }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        projectVM.handleDrop(providers: providers)
    }

    private func handleVideoChange(_ oldValue: VideoItem?, _ newVideo: VideoItem?) {
        guard let video = newVideo else { return }
        playerVM.loadVideo(video)
        cropEditorVM.bind(to: video)
        keyframeVM.bind(to: video, cropEditor: cropEditorVM)
        undoManager.bind(to: cropEditorVM)
        undoManager.clearHistory()

        // Set up auto-keyframe creation when crop editing ends
        cropEditorVM.onCropEditEnded = { [weak keyframeVM, weak playerVM, weak undoManager] in
            guard let keyframeVM = keyframeVM, let playerVM = playerVM else { return }
            // Auto-create or update keyframe when keyframes are enabled
            if keyframeVM.keyframesEnabled {
                let hadKeyframeAtTime = keyframeVM.hasKeyframe(at: playerVM.currentTime)
                keyframeVM.autoCreateKeyframe(at: playerVM.currentTime)
                // Record undo only for new keyframes
                if !hadKeyframeAtTime {
                    undoManager?.recordAction(type: .keyframeAdd)
                }
            }
        }
    }

    private func handleTimeChange(_ oldValue: Double, _ newTime: Double) {
        if keyframeVM.keyframesEnabled && keyframeVM.keyframes.count >= 2 {
            keyframeVM.applyKeyframeState(at: newTime)
        }
    }
}

// MARK: - Notification Handlers

struct FileNotificationHandler: ViewModifier {
    let projectVM: ProjectViewModel
    let exportVM: ExportViewModel
    let playerVM: VideoPlayerViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openVideos)) { _ in
                openFilePicker()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportVideo)) { _ in
                handleExport()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportAllVideos)) { _ in
                handleExportAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportJSON)) { _ in
                handleExportJSON()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportBoundingBox)) { _ in
                handleExportBoundingBox()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedVideo)) { _ in
                deleteSelectedVideo()
            }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        if panel.runModal() == .OK {
            Task { await projectVM.addVideos(from: panel.urls) }
        }
    }

    private func handleExport() {
        guard let video = projectVM.selectedVideo,
              video.hasCropChanges else { return }
        // Pause playback before export to avoid asset reader conflict
        playerVM.pause()
        Task {
            // Give player time to release the asset
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await exportVM.export(video: video)
        }
    }

    private func handleExportAll() {
        // Only batch export if user explicitly selected multiple videos (Shift/Cmd+click)
        guard projectVM.selectedVideoIDs.count > 1 else {
            // Fall back to single export
            handleExport()
            return
        }

        // Filter to only videos with crop changes
        let videosToExport = projectVM.selectedVideos.filter { $0.hasCropChanges }
        guard !videosToExport.isEmpty else { return }

        // Pause playback before export to avoid asset reader conflict
        playerVM.pause()
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await exportVM.exportAll(videos: videosToExport)
        }
    }

    private func deleteSelectedVideo() {
        guard let video = projectVM.selectedVideo else { return }
        projectVM.removeVideo(video)
    }

    private func handleExportJSON() {
        // Get videos to export (selected ones with crop changes)
        let videosToExport: [VideoItem]
        if projectVM.selectedVideoIDs.count > 1 {
            videosToExport = projectVM.selectedVideos.filter { $0.hasCropChanges }
        } else if let video = projectVM.selectedVideo, video.hasCropChanges {
            videosToExport = [video]
        } else {
            return
        }

        guard !videosToExport.isEmpty else { return }

        // Show folder picker
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder to export \(videosToExport.count) JSON file(s)"

        if panel.runModal() == .OK, let folderURL = panel.url {
            do {
                let exportedURLs = try CropDataStorageService.shared.exportMultipleToFolder(
                    videos: videosToExport,
                    destinationFolder: folderURL
                )
                // Show in Finder
                if !exportedURLs.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(exportedURLs)
                    print("Exported \(exportedURLs.count) JSON file(s) to \(folderURL.path)")
                }
            } catch {
                print("Failed to export JSON: \(error)")
            }
        }
    }

    private func handleExportBoundingBox() {
        // Get videos to export (selected ones with crop changes)
        let videosToExport: [VideoItem]
        if projectVM.selectedVideoIDs.count > 1 {
            videosToExport = projectVM.selectedVideos.filter { $0.hasCropChanges }
        } else if let video = projectVM.selectedVideo, video.hasCropChanges {
            videosToExport = [video]
        } else {
            return
        }

        guard !videosToExport.isEmpty else { return }

        // Show folder picker
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder to export \(videosToExport.count) bounding box file(s)\nFormat: [[x1, y1, x2, y2], ...] per frame"

        if panel.runModal() == .OK, let folderURL = panel.url {
            do {
                let exportedURLs = try CropDataStorageService.shared.exportMultipleBoundingBoxData(
                    videos: videosToExport,
                    destinationFolder: folderURL
                )
                // Show in Finder
                if !exportedURLs.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(exportedURLs)
                    print("Exported \(exportedURLs.count) bounding box file(s) to \(folderURL.path)")
                }
            } catch {
                // Show error alert
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}

/// Holds copied crop settings for paste functionality
struct CopiedCropSettings {
    let mode: CropMode
    let cropRect: CGRect
    let circleCenter: CGPoint
    let circleRadius: Double
    let freehandPoints: [CGPoint]
}

struct EditNotificationHandler: ViewModifier {
    let undoManager: CropUndoManager
    let cropEditorVM: CropEditorViewModel
    @Binding var copiedSettings: CopiedCropSettings?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .undoCrop)) { _ in
                undoManager.undo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .redoCrop)) { _ in
                undoManager.redo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetCrop)) { _ in
                undoManager.recordAction(type: .composite)
                cropEditorVM.reset()
            }
            .onReceive(NotificationCenter.default.publisher(for: .copyCropSettings)) { _ in
                copyCropSettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pasteCropSettings)) { _ in
                pasteCropSettings()
            }
    }

    private func copyCropSettings() {
        copiedSettings = CopiedCropSettings(
            mode: cropEditorVM.mode,
            cropRect: cropEditorVM.cropRect,
            circleCenter: cropEditorVM.circleCenter,
            circleRadius: cropEditorVM.circleRadius,
            freehandPoints: cropEditorVM.freehandPoints
        )
    }

    private func pasteCropSettings() {
        guard let settings = copiedSettings else { return }
        undoManager.recordAction(type: .composite)
        cropEditorVM.mode = settings.mode
        cropEditorVM.cropRect = settings.cropRect
        cropEditorVM.circleCenter = settings.circleCenter
        cropEditorVM.circleRadius = settings.circleRadius
        cropEditorVM.freehandPoints = settings.freehandPoints
    }
}

struct ViewNotificationHandler: ViewModifier {
    @Binding var viewScale: CGFloat
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let keyframeVM: KeyframeViewModel
    @Binding var isPreviewMode: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewScale = min(3.0, viewScale * 1.25)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewScale = max(0.5, viewScale / 1.25)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomReset)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewScale = 1.0
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomFit)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewScale = 1.0
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    columnVisibility = columnVisibility == .all ? .detailOnly : .all
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleKeyframeTimeline)) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    keyframeVM.keyframesEnabled.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePreviewMode)) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPreviewMode.toggle()
                }
            }
    }
}

struct CropNotificationHandler: ViewModifier {
    let undoManager: CropUndoManager
    let cropEditorVM: CropEditorViewModel
    let keyframeVM: KeyframeViewModel
    let playerVM: VideoPlayerViewModel

    // Nudge amount (1% of video)
    private let nudgeAmount: CGFloat = 0.01

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .setCropMode)) { notification in
                if let mode = notification.object as? CropMode {
                    undoManager.recordAction(type: .modeChange)
                    cropEditorVM.mode = mode
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .addKeyframe)) { _ in
                keyframeVM.addKeyframe(at: playerVM.currentTime)
                undoManager.recordAction(type: .keyframeAdd)
            }
            .onReceive(NotificationCenter.default.publisher(for: .removeKeyframe)) { _ in
                keyframeVM.removeKeyframe(at: playerVM.currentTime)
                undoManager.recordAction(type: .keyframeRemove)
            }
            .onReceive(NotificationCenter.default.publisher(for: .goToPreviousKeyframe)) { _ in
                goToPreviousKeyframe()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goToNextKeyframe)) { _ in
                goToNextKeyframe()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nudgeCropLeft)) { _ in
                nudgeCrop(dx: -nudgeAmount, dy: 0)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nudgeCropRight)) { _ in
                nudgeCrop(dx: nudgeAmount, dy: 0)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nudgeCropUp)) { _ in
                nudgeCrop(dx: 0, dy: -nudgeAmount)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nudgeCropDown)) { _ in
                nudgeCrop(dx: 0, dy: nudgeAmount)
            }
    }

    private func goToPreviousKeyframe() {
        let currentTime = playerVM.currentTime
        let previousKeyframes = keyframeVM.keyframes.filter { $0.timestamp < currentTime - 0.05 }
        if let previous = previousKeyframes.last {
            playerVM.seek(to: previous.timestamp)
            keyframeVM.selectKeyframe(previous)
        }
    }

    private func goToNextKeyframe() {
        let currentTime = playerVM.currentTime
        let nextKeyframes = keyframeVM.keyframes.filter { $0.timestamp > currentTime + 0.05 }
        if let next = nextKeyframes.first {
            playerVM.seek(to: next.timestamp)
            keyframeVM.selectKeyframe(next)
        }
    }

    private func nudgeCrop(dx: CGFloat, dy: CGFloat) {
        undoManager.beginDragOperation()

        switch cropEditorVM.mode {
        case .rectangle:
            var rect = cropEditorVM.cropRect
            rect.origin.x = max(0, min(1 - rect.width, rect.origin.x + dx))
            rect.origin.y = max(0, min(1 - rect.height, rect.origin.y + dy))
            cropEditorVM.cropRect = rect

        case .circle:
            var center = cropEditorVM.circleCenter
            center.x = max(cropEditorVM.circleRadius, min(1 - cropEditorVM.circleRadius, center.x + dx))
            center.y = max(cropEditorVM.circleRadius, min(1 - cropEditorVM.circleRadius, center.y + dy))
            cropEditorVM.circleCenter = center

        case .freehand:
            cropEditorVM.freehandPoints = cropEditorVM.freehandPoints.map { point in
                CGPoint(
                    x: max(0, min(1, point.x + dx)),
                    y: max(0, min(1, point.y + dy))
                )
            }
        }
    }
}

struct PlaybackNotificationHandler: ViewModifier {
    let playerVM: VideoPlayerViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .togglePlayPause)) { _ in
                playerVM.togglePlayPause()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stepForward)) { _ in
                playerVM.stepForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stepBackward)) { _ in
                playerVM.stepBackward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .playReverse)) { _ in
                playerVM.playReverse()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pausePlayback)) { _ in
                playerVM.pause()
            }
            .onReceive(NotificationCenter.default.publisher(for: .playForward)) { _ in
                playerVM.play()
            }
            .onReceive(NotificationCenter.default.publisher(for: .jumpForward)) { notification in
                if let seconds = notification.object as? Double {
                    playerVM.jumpForward(seconds: seconds)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jumpBackward)) { notification in
                if let seconds = notification.object as? Double {
                    playerVM.jumpBackward(seconds: seconds)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .goToStart)) { _ in
                playerVM.goToStart()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goToEnd)) { _ in
                playerVM.goToEnd()
            }
            .onReceive(NotificationCenter.default.publisher(for: .shuttleReverse)) { _ in
                playerVM.shuttleReverse()
            }
            .onReceive(NotificationCenter.default.publisher(for: .shuttleStop)) { _ in
                playerVM.shuttleStop()
            }
            .onReceive(NotificationCenter.default.publisher(for: .shuttleForward)) { _ in
                playerVM.shuttleForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .setPlaybackRate)) { notification in
                if let rate = notification.object as? Float {
                    playerVM.setPlaybackRate(rate)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleLoopPlayback)) { _ in
                playerVM.toggleLoop()
            }
    }
}

struct VideoSelectionNotificationHandler: ViewModifier {
    let projectVM: ProjectViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .selectNextVideo)) { _ in
                selectNextVideo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectPreviousVideo)) { _ in
                selectPreviousVideo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectAll)) { _ in
                selectAllVideos()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deselectAll)) { _ in
                deselectAllVideos()
            }
    }

    private func selectNextVideo() {
        guard let currentVideo = projectVM.selectedVideo,
              let currentIndex = projectVM.videos.firstIndex(where: { $0.id == currentVideo.id }),
              currentIndex < projectVM.videos.count - 1 else { return }
        projectVM.selectVideo(projectVM.videos[currentIndex + 1])
    }

    private func selectPreviousVideo() {
        guard let currentVideo = projectVM.selectedVideo,
              let currentIndex = projectVM.videos.firstIndex(where: { $0.id == currentVideo.id }),
              currentIndex > 0 else { return }
        projectVM.selectVideo(projectVM.videos[currentIndex - 1])
    }

    private func selectAllVideos() {
        projectVM.selectedVideoIDs = Set(projectVM.videos.map { $0.id })
        if projectVM.selectedVideo == nil, let first = projectVM.videos.first {
            projectVM.selectedVideo = first
        }
    }

    private func deselectAllVideos() {
        projectVM.selectedVideoIDs.removeAll()
        // Keep the primary selection
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    @EnvironmentObject var projectVM: ProjectViewModel

    var body: some View {
        ContentUnavailableView {
            Label("No Video Selected", systemImage: "film")
        } description: {
            Text("Drag and drop videos here or click + to add")
        } actions: {
            Button("Add Videos...") { openFilePicker() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        if panel.runModal() == .OK {
            Task { await projectVM.addVideos(from: panel.urls) }
        }
    }
}

#Preview {
    MainContentView()
        .environmentObject(ProjectViewModel())
}

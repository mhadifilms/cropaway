//
//  AppCommandHandler.swift
//  cropaway
//

import SwiftUI
import UniformTypeIdentifiers

/// Centralized command handler that replaces multiple NotificationCenter handlers
struct AppCommandHandler: ViewModifier {
    @Environment(\.commandDispatcher) private var commandDispatcher
    
    // View models
    let projectVM: ProjectViewModel
    let playerVM: VideoPlayerViewModel
    let cropEditorVM: CropEditorViewModel
    let keyframeVM: KeyframeViewModel
    let timelineVM: TimelineViewModel
    let undoManager: CropUndoManager
    
    // State
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var viewScale: CGFloat
    @Binding var isPreviewMode: Bool
    
    func body(content: Content) -> some View {
        content
            .onChange(of: commandDispatcher.lastCommand) { oldValue, newValue in
                guard let command = newValue else { return }
                handleCommand(command)
                commandDispatcher.clearLastCommand()
            }
    }
    
    private func handleCommand(_ command: AppCommand) {
        switch command {
        // MARK: - File
        case .openVideos:
            openFilePicker()
            
        case .exportCurrentVideo:
            handleExport()
            
        case .exportCropJSON:
            handleExportJSON()
            
        case .closeVideo:
            deleteSelectedVideo()
            
        case .delete:
            deleteSelectedVideo()
            
        // MARK: - Edit
        case .undo:
            undoManager.undo()
            
        case .redo:
            undoManager.redo()
            
        case .selectAll:
            selectAllVideos()
            
        case .resetCrop:
            undoManager.recordAction(type: .composite)
            cropEditorVM.reset()
            if let video = projectVM.selectedVideo {
                video.clearSavedCropData()
            }
            
        // MARK: - View
        case .toggleSidebar:
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
            
        case .zoomIn:
            withAnimation(.easeInOut(duration: 0.15)) {
                viewScale = min(3.0, viewScale * 1.25)
            }
            
        case .zoomOut:
            withAnimation(.easeInOut(duration: 0.15)) {
                viewScale = max(0.5, viewScale / 1.25)
            }
            
        case .zoomToFit:
            withAnimation(.easeInOut(duration: 0.15)) {
                viewScale = 1.0
            }
            
        case .actualSize:
            withAnimation(.easeInOut(duration: 0.15)) {
                viewScale = 1.0
            }
            
        case .toggleFullScreen:
            NSApplication.shared.keyWindow?.toggleFullScreen(nil)
            
        case .toggleKeyframes:
            withAnimation(.easeInOut(duration: 0.2)) {
                keyframeVM.keyframesEnabled.toggle()
            }
            
        case .toggleTimeline:
            withAnimation(.easeInOut(duration: 0.2)) {
                timelineVM.toggleTimelinePanel(startingWith: projectVM.selectedVideo)
            }
            
        // MARK: - Crop
        case .setCropMode(let mode):
            undoManager.recordAction(type: .modeChange)
            cropEditorVM.mode = mode
            
        case .addKeyframe:
            keyframeVM.addKeyframe(at: playerVM.currentTime)
            undoManager.recordAction(type: .keyframeAdd)
            
        case .deleteKeyframe:
            keyframeVM.removeKeyframe(at: playerVM.currentTime)
            undoManager.recordAction(type: .keyframeRemove)
            
        // MARK: - Playback
        case .playPause:
            playerVM.togglePlayPause()
            
        case .stepForward:
            playerVM.stepForward()
            
        case .stepBackward:
            playerVM.stepBackward()
            
        case .shuttleBackward:
            playerVM.shuttleReverse()
            
        case .shuttleStop:
            playerVM.shuttleStop()
            
        case .shuttleForward:
            playerVM.shuttleForward()
            
        case .setPlaybackRate(let rate):
            playerVM.setPlaybackRate(rate)
            
        case .toggleLoop:
            playerVM.toggleLoop()
            
        case .toggleFrameDisplay:
            playerVM.showFrameCount.toggle()
            
        // MARK: - Timeline
        case .splitClipAtPlayhead:
            _ = timelineVM.splitSelectedClipAtPlayhead()
            
        case .goToNextClip:
            timelineVM.goToNextClip()
            
        case .goToPreviousClip:
            timelineVM.goToPreviousClip()
        }
    }
    
    // MARK: - Helper Methods
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .mpeg2Video, .video]
        
        panel.begin { response in
            if response == .OK {
                Task { @MainActor in
                    await projectVM.addVideos(from: panel.urls)
                }
            }
        }
    }
    
    private func handleExport() {
        guard let video = projectVM.selectedVideo else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.nameFieldStringValue = video.fileName.replacingOccurrences(of: ".mp4", with: "_cropped.mp4")
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                Task { @MainActor in
                    // Export logic handled by ExportViewModel
                }
            }
        }
    }
    
    private func handleExportJSON() {
        guard let video = projectVM.selectedVideo else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = video.fileName.replacingOccurrences(of: ".mp4", with: "_crop.json")
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                // TODO: Implement JSON export
                print("Export JSON to: \(url)")
            }
        }
    }
    
    private func deleteSelectedVideo() {
        if let video = projectVM.selectedVideo {
            projectVM.removeVideo(video)
        }
    }
    
    private func selectAllVideos() {
        // Select all videos in project
        if let firstVideo = projectVM.videos.first {
            projectVM.selectVideo(firstVideo)
        }
    }
}

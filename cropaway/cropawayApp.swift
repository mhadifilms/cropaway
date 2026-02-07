//
//  CropawayApp.swift
//  Cropaway
//

import SwiftUI

@main
struct CropawayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var projectVM = ProjectViewModel()
    @StateObject private var updateService = UpdateService.shared

    @State private var showUpdateDialog = false
    @State private var showUpdateCheckResult = false

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environment(projectVM)
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: $showUpdateDialog) {
                    UpdateAvailableView(updateService: updateService)
                }
                .sheet(isPresented: $showUpdateCheckResult) {
                    UpdateCheckView(updateService: updateService)
                }
                .onReceive(NotificationCenter.default.publisher(for: .showUpdateDialog)) { _ in
                    showUpdateDialog = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .checkForUpdates)) { _ in
                    Task {
                        await updateService.checkForUpdates(force: true)
                        showUpdateCheckResult = true
                    }
                }
                .task {
                    // Check for updates on launch (if 24h has passed)
                    if updateService.shouldCheckAutomatically {
                        await updateService.checkForUpdates()
                        if case .available = updateService.status {
                            showUpdateDialog = true
                        }
                    }
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            CropawayCommands()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure window for glass effect
        configureWindowForGlass()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup on app quit (if needed)
    }

    private func configureWindowForGlass() {
        guard let window = NSApplication.shared.windows.first else { return }

        if #available(macOS 26.0, *) {
            // macOS 26: Use glass-compatible window styling
            window.isOpaque = false
            window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.8)
            window.titlebarAppearsTransparent = true
        } else {
            // Earlier macOS: Standard window background
            window.titlebarAppearsTransparent = true
        }
    }
}

struct CropawayCommands: Commands {
    @Environment(\.commandDispatcher) private var commands
    
    var body: some Commands {
        // App menu - Check for Updates
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                NotificationCenter.default.post(name: .checkForUpdates, object: nil)
            }
        }

        // File menu
        CommandGroup(after: .newItem) {
            Button("Add Videos...") {
                commands.send(.openVideos)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Videos...") {
                commands.send(.openVideos)
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Export...") {
                commands.send(.exportCurrentVideo)
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("Export Crop JSON...") {
                commands.send(.exportCropJSON)
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])

            Divider()

            Button("Remove Selected Video") {
                commands.send(.delete)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }

        // Edit menu - Undo/Redo
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                commands.send(.undo)
            }
            .keyboardShortcut("z", modifiers: .command)

            Button("Redo") {
                commands.send(.redo)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider()
        }

        // Edit menu additions
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Reset Crop") {
                commands.send(.resetCrop)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Select All") {
                commands.send(.selectAll)
            }
            .keyboardShortcut("a", modifiers: .command)
        }

        // View menu - Zoom and Display
        CommandMenu("View") {
            Button("Zoom In") {
                commands.send(.zoomIn)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom Out") {
                commands.send(.zoomOut)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                commands.send(.actualSize)
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("Fit to Window") {
                commands.send(.zoomToFit)
            }
            .keyboardShortcut("9", modifiers: .command)

            Divider()

            Button("Toggle Sidebar") {
                commands.send(.toggleSidebar)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Button("Toggle Keyframes") {
                commands.send(.toggleKeyframes)
            }
            .keyboardShortcut("4", modifiers: [.command, .control])
            
            Button("Toggle Timeline") {
                commands.send(.toggleTimeline)
            }
            .keyboardShortcut("5", modifiers: .command)

            Divider()

            Button("Toggle Full Screen") {
                commands.send(.toggleFullScreen)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }

        // Crop menu
        CommandMenu("Crop") {
            Button("Rectangle") {
                commands.send(.setCropMode(.rectangle))
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Circle") {
                commands.send(.setCropMode(.circle))
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Custom Mask") {
                commands.send(.setCropMode(.freehand))
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("AI Track") {
                commands.send(.setCropMode(.ai))
            }
            .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Add Keyframe") {
                commands.send(.addKeyframe)
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Remove Keyframe") {
                commands.send(.deleteKeyframe)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        // Playback menu
        CommandMenu("Playback") {
            Button("Play/Pause") {
                commands.send(.playPause)
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button("Step Forward") {
                commands.send(.stepForward)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Step Backward") {
                commands.send(.stepBackward)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Divider()

            Button("Shuttle Backward (J)") {
                commands.send(.shuttleBackward)
            }
            .keyboardShortcut("j", modifiers: [])

            Button("Shuttle Stop (K)") {
                commands.send(.shuttleStop)
            }
            .keyboardShortcut("k", modifiers: [])

            Button("Shuttle Forward (L)") {
                commands.send(.shuttleForward)
            }
            .keyboardShortcut("l", modifiers: [])

            Divider()

            Button("Slow Motion (50%)") {
                commands.send(.setPlaybackRate(0.5))
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Normal Speed") {
                commands.send(.setPlaybackRate(1.0))
            }
            .keyboardShortcut("d", modifiers: [.command, .option])

            Button("Fast Forward (2x)") {
                commands.send(.setPlaybackRate(2.0))
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Divider()

            Button("Loop Playback") {
                commands.send(.toggleLoop)
            }
            .keyboardShortcut("l", modifiers: .command)
            
            Button("Toggle Frame Display") {
                commands.send(.toggleFrameDisplay)
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
        }

        // Timeline menu
        CommandMenu("Timeline") {
            Button("Split Clip at Playhead") {
                commands.send(.splitClipAtPlayhead)
            }
            .keyboardShortcut("b", modifiers: .command)
            
            Divider()
            
            Button("Go to Next Clip") {
                commands.send(.goToNextClip)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            
            Button("Go to Previous Clip") {
                commands.send(.goToPreviousClip)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Add Selected to Sequence") {
                NotificationCenter.default.post(name: .addToSequence, object: nil)
            }
            .keyboardShortcut("=", modifiers: .command)
            
            Button("Add Video to Timeline...") {
                NotificationCenter.default.post(name: .addVideoToTimeline, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Set In Point") {
                NotificationCenter.default.post(name: .setInPoint, object: nil)
            }
            .keyboardShortcut("i", modifiers: [])

            Button("Set Out Point") {
                NotificationCenter.default.post(name: .setOutPoint, object: nil)
            }
            .keyboardShortcut("o", modifiers: [])

            Button("Split Clip") {
                NotificationCenter.default.post(name: .splitClip, object: nil)
            }
            .keyboardShortcut("b", modifiers: .command)

            Divider()

            Button("Next Clip") {
                NotificationCenter.default.post(name: .nextClip, object: nil)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Previous Clip") {
                NotificationCenter.default.post(name: .previousClip, object: nil)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Divider()

            Button("Export Sequence...") {
                NotificationCenter.default.post(name: .exportSequence, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
        }

        // Window menu additions
        CommandGroup(after: .windowSize) {
            Button("Next Video") {
                NotificationCenter.default.post(name: .selectNextVideo, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)

            Button("Previous Video") {
                NotificationCenter.default.post(name: .selectPreviousVideo, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
        }
    }
}

extension Notification.Name {
    // File operations
    static let openVideos = Notification.Name("openVideos")
    static let exportVideo = Notification.Name("exportVideo")
    static let exportAllVideos = Notification.Name("exportAllVideos")
    static let exportJSON = Notification.Name("exportJSON")
    static let exportBoundingBox = Notification.Name("exportBoundingBox")
    static let exportBoundingBoxPickle = Notification.Name("exportBoundingBoxPickle")
    static let deleteSelectedVideo = Notification.Name("deleteSelectedVideo")

    // Edit operations
    static let undoCrop = Notification.Name("undoCrop")
    static let redoCrop = Notification.Name("redoCrop")
    static let resetCrop = Notification.Name("resetCrop")
    static let copyCropSettings = Notification.Name("copyCropSettings")
    static let pasteCropSettings = Notification.Name("pasteCropSettings")
    static let selectAll = Notification.Name("selectAll")
    static let deselectAll = Notification.Name("deselectAll")

    // View operations
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")
    static let zoomFit = Notification.Name("zoomFit")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let toggleKeyframeTimeline = Notification.Name("toggleKeyframeTimeline")
    static let togglePreviewMode = Notification.Name("togglePreviewMode")

    // Crop operations
    static let setCropMode = Notification.Name("setCropMode")
    static let addKeyframe = Notification.Name("addKeyframe")
    static let removeKeyframe = Notification.Name("removeKeyframe")
    static let goToPreviousKeyframe = Notification.Name("goToPreviousKeyframe")
    static let goToNextKeyframe = Notification.Name("goToNextKeyframe")
    static let nudgeCropLeft = Notification.Name("nudgeCropLeft")
    static let nudgeCropRight = Notification.Name("nudgeCropRight")
    static let nudgeCropUp = Notification.Name("nudgeCropUp")
    static let nudgeCropDown = Notification.Name("nudgeCropDown")

    // Playback operations
    static let togglePlayPause = Notification.Name("togglePlayPause")
    static let stepForward = Notification.Name("stepForward")
    static let stepBackward = Notification.Name("stepBackward")
    static let playReverse = Notification.Name("playReverse")
    static let pausePlayback = Notification.Name("pausePlayback")
    static let playForward = Notification.Name("playForward")
    static let jumpForward = Notification.Name("jumpForward")
    static let jumpBackward = Notification.Name("jumpBackward")
    static let goToStart = Notification.Name("goToStart")
    static let goToEnd = Notification.Name("goToEnd")
    static let shuttleReverse = Notification.Name("shuttleReverse")
    static let shuttleStop = Notification.Name("shuttleStop")
    static let shuttleForward = Notification.Name("shuttleForward")
    static let setPlaybackRate = Notification.Name("setPlaybackRate")
    static let toggleLoopPlayback = Notification.Name("toggleLoopPlayback")

    // Video selection
    static let selectNextVideo = Notification.Name("selectNextVideo")
    static let selectPreviousVideo = Notification.Name("selectPreviousVideo")

    // Sequence operations
    static let createSequence = Notification.Name("createSequence")
    static let toggleSequenceMode = Notification.Name("toggleSequenceMode")
    static let addToSequence = Notification.Name("addToSequence")
    static let addVideoToTimeline = Notification.Name("addVideoToTimeline")
    static let splitClip = Notification.Name("splitClip")
    static let setInPoint = Notification.Name("setInPoint")
    static let setOutPoint = Notification.Name("setOutPoint")
    static let exportSequence = Notification.Name("exportSequence")
    static let nextClip = Notification.Name("nextClip")
    static let previousClip = Notification.Name("previousClip")
}

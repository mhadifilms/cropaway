//
//  CropawayApp.swift
//  Cropaway
//

import SwiftUI

@main
struct CropawayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var projectVM = ProjectViewModel()
    @StateObject private var updateService = UpdateService.shared

    @State private var showUpdateDialog = false
    @State private var showUpdateCheckResult = false

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(projectVM)
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
                NotificationCenter.default.post(name: .openVideos, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Videos...") {
                NotificationCenter.default.post(name: .openVideos, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Export...") {
                NotificationCenter.default.post(name: .exportVideo, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("Export All...") {
                NotificationCenter.default.post(name: .exportAllVideos, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button("Remove Selected Video") {
                NotificationCenter.default.post(name: .deleteSelectedVideo, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }

        // Edit menu - Undo/Redo
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                NotificationCenter.default.post(name: .undoCrop, object: nil)
            }
            .keyboardShortcut("z", modifiers: .command)

            Button("Redo") {
                NotificationCenter.default.post(name: .redoCrop, object: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider()
        }

        // Edit menu additions
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Copy Crop Settings") {
                NotificationCenter.default.post(name: .copyCropSettings, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Paste Crop Settings") {
                NotificationCenter.default.post(name: .pasteCropSettings, object: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Divider()

            Button("Reset Crop") {
                NotificationCenter.default.post(name: .resetCrop, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Select All") {
                NotificationCenter.default.post(name: .selectAll, object: nil)
            }
            .keyboardShortcut("a", modifiers: .command)
        }

        // View menu - Zoom and Display
        CommandMenu("View") {
            Button("Zoom In") {
                NotificationCenter.default.post(name: .zoomIn, object: nil)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom Out") {
                NotificationCenter.default.post(name: .zoomOut, object: nil)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                NotificationCenter.default.post(name: .zoomReset, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("Fit to Window") {
                NotificationCenter.default.post(name: .zoomFit, object: nil)
            }
            .keyboardShortcut("9", modifiers: .command)

            Divider()

            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Button("Toggle Keyframe Timeline") {
                NotificationCenter.default.post(name: .toggleKeyframeTimeline, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .control])

            Divider()

            Button("Toggle Preview Mode") {
                NotificationCenter.default.post(name: .togglePreviewMode, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        // Crop menu
        CommandMenu("Crop") {
            Button("Rectangle") {
                NotificationCenter.default.post(name: .setCropMode, object: CropMode.rectangle)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Circle") {
                NotificationCenter.default.post(name: .setCropMode, object: CropMode.circle)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Custom Mask") {
                NotificationCenter.default.post(name: .setCropMode, object: CropMode.freehand)
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("AI Track") {
                NotificationCenter.default.post(name: .setCropMode, object: CropMode.ai)
            }
            .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Add Keyframe") {
                NotificationCenter.default.post(name: .addKeyframe, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Remove Keyframe") {
                NotificationCenter.default.post(name: .removeKeyframe, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Button("Previous Keyframe") {
                NotificationCenter.default.post(name: .goToPreviousKeyframe, object: nil)
            }
            .keyboardShortcut("[", modifiers: .command)

            Button("Next Keyframe") {
                NotificationCenter.default.post(name: .goToNextKeyframe, object: nil)
            }
            .keyboardShortcut("]", modifiers: .command)

            Divider()

            Button("Nudge Left") {
                NotificationCenter.default.post(name: .nudgeCropLeft, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .option)

            Button("Nudge Right") {
                NotificationCenter.default.post(name: .nudgeCropRight, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .option)

            Button("Nudge Up") {
                NotificationCenter.default.post(name: .nudgeCropUp, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: .option)

            Button("Nudge Down") {
                NotificationCenter.default.post(name: .nudgeCropDown, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: .option)
        }

        // Playback menu
        CommandMenu("Playback") {
            Button("Play/Pause") {
                NotificationCenter.default.post(name: .togglePlayPause, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button("Step Forward") {
                NotificationCenter.default.post(name: .stepForward, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Step Backward") {
                NotificationCenter.default.post(name: .stepBackward, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Jump Forward 1 Second") {
                NotificationCenter.default.post(name: .jumpForward, object: 1.0)
            }
            .keyboardShortcut(.rightArrow, modifiers: .shift)

            Button("Jump Backward 1 Second") {
                NotificationCenter.default.post(name: .jumpBackward, object: 1.0)
            }
            .keyboardShortcut(.leftArrow, modifiers: .shift)

            Button("Jump Forward 10 Seconds") {
                NotificationCenter.default.post(name: .jumpForward, object: 10.0)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.shift, .command])

            Button("Jump Backward 10 Seconds") {
                NotificationCenter.default.post(name: .jumpBackward, object: 10.0)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.shift, .command])

            Divider()

            Button("Go to Start") {
                NotificationCenter.default.post(name: .goToStart, object: nil)
            }
            .keyboardShortcut(.home, modifiers: [])

            Button("Go to End") {
                NotificationCenter.default.post(name: .goToEnd, object: nil)
            }
            .keyboardShortcut(.end, modifiers: [])

            Divider()

            Button("Shuttle Reverse (J)") {
                NotificationCenter.default.post(name: .shuttleReverse, object: nil)
            }
            .keyboardShortcut("j", modifiers: [])

            Button("Shuttle Stop (K)") {
                NotificationCenter.default.post(name: .shuttleStop, object: nil)
            }
            .keyboardShortcut("k", modifiers: [])

            Button("Shuttle Forward (L)") {
                NotificationCenter.default.post(name: .shuttleForward, object: nil)
            }
            .keyboardShortcut("l", modifiers: [])

            Divider()

            Button("Slow Motion (50%)") {
                NotificationCenter.default.post(name: .setPlaybackRate, object: Float(0.5))
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Normal Speed") {
                NotificationCenter.default.post(name: .setPlaybackRate, object: Float(1.0))
            }
            .keyboardShortcut("d", modifiers: [.command, .option])

            Button("Fast Forward (2x)") {
                NotificationCenter.default.post(name: .setPlaybackRate, object: Float(2.0))
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Divider()

            Button("Loop Playback") {
                NotificationCenter.default.post(name: .toggleLoopPlayback, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)
        }
        
        // Timeline menu (timeline-native mode)
        CommandMenu("Timeline") {
            Button("Split Clip at Playhead") {
                NotificationCenter.default.post(name: .splitClipAtPlayhead, object: nil)
            }
            .keyboardShortcut("b", modifiers: .command)
            
            Divider()
            
            Button("Delete Selected Clips") {
                NotificationCenter.default.post(name: .deleteSelectedClips, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [])
            
            Button("Ripple Delete Selected Clips") {
                NotificationCenter.default.post(name: .rippleDeleteSelectedClips, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .shift)
            
            Divider()
            
            Button("Select Next Clip") {
                NotificationCenter.default.post(name: .selectNextClip, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            
            Button("Select Previous Clip") {
                NotificationCenter.default.post(name: .selectPreviousClip, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            
            Divider()
            
            Button("Set In Point") {
                NotificationCenter.default.post(name: .setInPoint, object: nil)
            }
            .keyboardShortcut("i", modifiers: [])
            
            Button("Set Out Point") {
                NotificationCenter.default.post(name: .setOutPoint, object: nil)
            }
            .keyboardShortcut("o", modifiers: [])
            
            Button("Clear In/Out Points") {
                NotificationCenter.default.post(name: .clearInOutPoints, object: nil)
            }
            .keyboardShortcut("x", modifiers: [.command, .option])
            
            Divider()
            
            Button("Go to In Point") {
                NotificationCenter.default.post(name: .goToInPoint, object: nil)
            }
            .keyboardShortcut("i", modifiers: .shift)
            
            Button("Go to Out Point") {
                NotificationCenter.default.post(name: .goToOutPoint, object: nil)
            }
            .keyboardShortcut("o", modifiers: .shift)
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
    
    // Timeline operations (timeline-native mode)
    static let splitClipAtPlayhead = Notification.Name("splitClipAtPlayhead")
    static let deleteSelectedClips = Notification.Name("deleteSelectedClips")
    static let rippleDeleteSelectedClips = Notification.Name("rippleDeleteSelectedClips")
    static let selectNextClip = Notification.Name("selectNextClip")
    static let selectPreviousClip = Notification.Name("selectPreviousClip")
    static let setInPoint = Notification.Name("setInPoint")
    static let setOutPoint = Notification.Name("setOutPoint")
    static let clearInOutPoints = Notification.Name("clearInOutPoints")
    static let goToInPoint = Notification.Name("goToInPoint")
    static let goToOutPoint = Notification.Name("goToOutPoint")
}

//
//  AppCommand.swift
//  cropaway
//

import Foundation
import SwiftUI

/// Type-safe application commands that replace NotificationCenter pattern
enum AppCommand: Equatable {
    // MARK: - File Menu
    case openVideos
    case exportCurrentVideo
    case exportCropJSON
    case closeVideo
    
    // MARK: - Edit Menu
    case undo
    case redo
    case delete
    case selectAll
    
    // MARK: - View Menu
    case toggleSidebar
    case zoomIn
    case zoomOut
    case zoomToFit
    case actualSize
    case toggleFullScreen
    
    // MARK: - Crop Menu
    case setCropMode(CropMode)
    case resetCrop
    case toggleKeyframes
    case addKeyframe
    case deleteKeyframe
    case toggleTimeline
    
    // MARK: - Playback
    case playPause
    case stepForward
    case stepBackward
    case toggleLoop
    case toggleFrameDisplay
    case setPlaybackRate(Float)
    case shuttleBackward
    case shuttleStop
    case shuttleForward
    
    // MARK: - Timeline
    case splitClipAtPlayhead
    case goToNextClip
    case goToPreviousClip
}

/// Observable command dispatcher that replaces NotificationCenter
@Observable
@MainActor
final class AppCommandDispatcher {
    /// Singleton instance
    static let shared = AppCommandDispatcher()
    
    /// Most recent command sent
    private(set) var lastCommand: AppCommand?
    
    /// Command history for debugging
    private(set) var commandHistory: [AppCommand] = []
    
    /// Maximum history size
    private let maxHistorySize = 50
    
    private init() {}
    
    /// Send a command through the app
    func send(_ command: AppCommand) {
        lastCommand = command
        
        // Keep command history for debugging
        commandHistory.append(command)
        if commandHistory.count > maxHistorySize {
            commandHistory.removeFirst()
        }
    }
    
    /// Clear the last command (useful for one-time commands)
    func clearLastCommand() {
        lastCommand = nil
    }
}

/// Environment key for command dispatcher
struct AppCommandDispatcherKey: EnvironmentKey {
    static let defaultValue = AppCommandDispatcher.shared
}

extension EnvironmentValues {
    var commandDispatcher: AppCommandDispatcher {
        get { self[AppCommandDispatcherKey.self] }
        set { self[AppCommandDispatcherKey.self] = newValue }
    }
}

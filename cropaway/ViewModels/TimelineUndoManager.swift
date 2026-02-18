//
//  TimelineUndoManager.swift
//  cropaway
//
//  PHASE 10: Undo/redo system for timeline operations
//

import Foundation
import Observation

/// Action types that can be undone/redone
enum TimelineAction {
    case addClip(clip: TimelineClip, trackIndex: Int, clipIndex: Int)
    case removeClip(clip: TimelineClip, trackIndex: Int, clipIndex: Int)
    case moveClip(clipID: UUID, fromTrack: Int, fromIndex: Int, toTrack: Int, toIndex: Int)
    case trimClip(clipID: UUID, oldInPoint: Double, oldOutPoint: Double, newInPoint: Double, newOutPoint: Double)
    case transformClip(clipID: UUID, oldTransform: ClipTransform, newTransform: ClipTransform)
    case addTrack(track: Track, index: Int)
    case removeTrack(track: Track, index: Int)
    case setInOutPoints(oldIn: Double?, oldOut: Double?, newIn: Double?, newOut: Double?)
}

/// Stores transform state for undo/redo
struct ClipTransform {
    let scale: CGFloat
    let positionX: Double
    let positionY: Double
    let rotation: Double
    let flipHorizontal: Bool
    let flipVertical: Bool
    let opacity: Double
    let volume: Float
    let isMuted: Bool
    
    init(from clip: TimelineClip) {
        self.scale = clip.scale
        self.positionX = clip.positionX
        self.positionY = clip.positionY
        self.rotation = clip.rotation
        self.flipHorizontal = clip.flipHorizontal
        self.flipVertical = clip.flipVertical
        self.opacity = clip.opacity
        self.volume = clip.volume
        self.isMuted = clip.isMuted
    }
    
    func apply(to clip: TimelineClip) {
        clip.scale = scale
        clip.positionX = positionX
        clip.positionY = positionY
        clip.rotation = rotation
        clip.flipHorizontal = flipHorizontal
        clip.flipVertical = flipVertical
        clip.opacity = opacity
        clip.volume = volume
        clip.isMuted = isMuted
    }
}

/// Manages undo/redo for timeline operations
@Observable
@MainActor
final class TimelineUndoManager {
    
    /// Maximum number of undo actions to store
    private let maxUndoStackSize = 50
    
    /// Stack of actions that can be undone
    private var undoStack: [TimelineAction] = []
    
    /// Stack of actions that can be redone
    private var redoStack: [TimelineAction] = []
    
    /// Reference to the timeline
    weak var timeline: Timeline?
    
    /// Whether there are actions that can be undone
    var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    /// Whether there are actions that can be redone
    var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    // MARK: - Recording Actions
    
    /// Record an action for undo
    func record(_ action: TimelineAction) {
        undoStack.append(action)
        
        // Clear redo stack when new action is recorded
        redoStack.removeAll()
        
        // Limit undo stack size
        if undoStack.count > maxUndoStackSize {
            undoStack.removeFirst()
        }
        
        print("📝 Recorded action: \(actionDescription(action))")
    }
    
    // MARK: - Undo/Redo
    
    /// Undo the last action
    func undo() {
        guard let action = undoStack.popLast() else { return }
        guard let timeline = timeline else { return }
        
        performUndo(action, on: timeline)
        redoStack.append(action)
        
        print("↩️ Undid: \(actionDescription(action))")
    }
    
    /// Redo the last undone action
    func redo() {
        guard let action = redoStack.popLast() else { return }
        guard let timeline = timeline else { return }
        
        performRedo(action, on: timeline)
        undoStack.append(action)
        
        print("↪️ Redid: \(actionDescription(action))")
    }
    
    /// Clear all undo/redo history
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
    
    // MARK: - Action Execution
    
    private func performUndo(_ action: TimelineAction, on timeline: Timeline) {
        switch action {
        case .addClip(let clip, let trackIndex, _):
            // Undo add = remove
            if trackIndex < timeline.tracks.count {
                timeline.tracks[trackIndex].clips.removeAll { $0.id == clip.id }
            }
            
        case .removeClip(let clip, let trackIndex, let clipIndex):
            // Undo remove = add back
            if trackIndex < timeline.tracks.count {
                let insertIndex = min(clipIndex, timeline.tracks[trackIndex].clips.count)
                timeline.tracks[trackIndex].clips.insert(clip, at: insertIndex)
            }
            
        case .moveClip(let clipID, let fromTrack, let fromIndex, let toTrack, _):
            // Move back to original position
            if let clip = timeline.tracks[toTrack].clips.first(where: { $0.id == clipID }) {
                timeline.tracks[toTrack].clips.removeAll { $0.id == clipID }
                timeline.tracks[fromTrack].clips.insert(clip, at: fromIndex)
            }
            
        case .trimClip(let clipID, let oldInPoint, let oldOutPoint, _, _):
            // Restore old trim points
            if let clip = timeline.findClip(withID: clipID) {
                clip.inPoint = oldInPoint
                clip.outPoint = oldOutPoint
            }
            
        case .transformClip(let clipID, let oldTransform, _):
            // Restore old transform
            if let clip = timeline.findClip(withID: clipID) {
                oldTransform.apply(to: clip)
            }
            
        case .addTrack(let track, _):
            // Undo add = remove
            timeline.tracks.removeAll { $0.id == track.id }
            
        case .removeTrack(let track, let index):
            // Undo remove = add back
            let insertIndex = min(index, timeline.tracks.count)
            timeline.tracks.insert(track, at: insertIndex)
            
        case .setInOutPoints(let oldIn, let oldOut, _, _):
            // Restore old in/out points
            timeline.inPoint = oldIn
            timeline.outPoint = oldOut
        }
    }
    
    private func performRedo(_ action: TimelineAction, on timeline: Timeline) {
        switch action {
        case .addClip(let clip, let trackIndex, let clipIndex):
            // Redo add
            if trackIndex < timeline.tracks.count {
                let insertIndex = min(clipIndex, timeline.tracks[trackIndex].clips.count)
                timeline.tracks[trackIndex].clips.insert(clip, at: insertIndex)
            }
            
        case .removeClip(let clip, let trackIndex, _):
            // Redo remove
            if trackIndex < timeline.tracks.count {
                timeline.tracks[trackIndex].clips.removeAll { $0.id == clip.id }
            }
            
        case .moveClip(let clipID, let fromTrack, _, let toTrack, let toIndex):
            // Move to new position
            if let clip = timeline.tracks[fromTrack].clips.first(where: { $0.id == clipID }) {
                timeline.tracks[fromTrack].clips.removeAll { $0.id == clipID }
                timeline.tracks[toTrack].clips.insert(clip, at: toIndex)
            }
            
        case .trimClip(let clipID, _, _, let newInPoint, let newOutPoint):
            // Apply new trim points
            if let clip = timeline.findClip(withID: clipID) {
                clip.inPoint = newInPoint
                clip.outPoint = newOutPoint
            }
            
        case .transformClip(let clipID, _, let newTransform):
            // Apply new transform
            if let clip = timeline.findClip(withID: clipID) {
                newTransform.apply(to: clip)
            }
            
        case .addTrack(let track, let index):
            // Redo add
            let insertIndex = min(index, timeline.tracks.count)
            timeline.tracks.insert(track, at: insertIndex)
            
        case .removeTrack(let track, _):
            // Redo remove
            timeline.tracks.removeAll { $0.id == track.id }
            
        case .setInOutPoints(_, _, let newIn, let newOut):
            // Apply new in/out points
            timeline.inPoint = newIn
            timeline.outPoint = newOut
        }
    }
    
    // MARK: - Helper
    
    private func actionDescription(_ action: TimelineAction) -> String {
        switch action {
        case .addClip: return "Add Clip"
        case .removeClip: return "Remove Clip"
        case .moveClip: return "Move Clip"
        case .trimClip: return "Trim Clip"
        case .transformClip: return "Transform Clip"
        case .addTrack: return "Add Track"
        case .removeTrack: return "Remove Track"
        case .setInOutPoints: return "Set In/Out Points"
        }
    }
}

//
//  CropUndoManager.swift
//  cropaway
//

import Foundation
import CoreGraphics
import Combine

/// Represents a single undoable action in the crop editor
struct CropUndoAction {
    enum ActionType {
        case cropRectChange
        case modeChange
        case circleChange
        case freehandChange
        case keyframeAdd
        case keyframeRemove
        case composite // Multiple changes grouped together
    }

    let type: ActionType
    let timestamp: Date

    // State before the action
    let previousCropRect: CGRect
    let previousMode: CropMode
    let previousCircleCenter: CGPoint
    let previousCircleRadius: Double
    let previousFreehandPoints: [CGPoint]

    // State after the action
    let newCropRect: CGRect
    let newMode: CropMode
    let newCircleCenter: CGPoint
    let newCircleRadius: Double
    let newFreehandPoints: [CGPoint]

    init(
        type: ActionType,
        previousCropRect: CGRect,
        previousMode: CropMode,
        previousCircleCenter: CGPoint,
        previousCircleRadius: Double,
        previousFreehandPoints: [CGPoint],
        newCropRect: CGRect,
        newMode: CropMode,
        newCircleCenter: CGPoint,
        newCircleRadius: Double,
        newFreehandPoints: [CGPoint]
    ) {
        self.type = type
        self.timestamp = Date()
        self.previousCropRect = previousCropRect
        self.previousMode = previousMode
        self.previousCircleCenter = previousCircleCenter
        self.previousCircleRadius = previousCircleRadius
        self.previousFreehandPoints = previousFreehandPoints
        self.newCropRect = newCropRect
        self.newMode = newMode
        self.newCircleCenter = newCircleCenter
        self.newCircleRadius = newCircleRadius
        self.newFreehandPoints = newFreehandPoints
    }
}

/// Manages undo/redo stack for crop operations
@MainActor
final class CropUndoManager: ObservableObject {
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false

    private var undoStack: [CropUndoAction] = []
    private var redoStack: [CropUndoAction] = []

    // Debounce timer for grouping rapid drag changes
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.3

    // Pending state for debounced changes
    private var pendingActionStart: CropUndoAction?
    private var isRecordingDrag: Bool = false

    // Reference to the crop editor
    private weak var cropEditor: CropEditorViewModel?

    // Current state snapshot
    private var lastKnownState: (
        cropRect: CGRect,
        mode: CropMode,
        circleCenter: CGPoint,
        circleRadius: Double,
        freehandPoints: [CGPoint]
    )?

    deinit {
        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    func bind(to cropEditor: CropEditorViewModel) {
        self.cropEditor = cropEditor
        snapshotCurrentState()
    }

    private func snapshotCurrentState() {
        guard let cropEditor = cropEditor else { return }
        lastKnownState = (
            cropRect: cropEditor.cropRect,
            mode: cropEditor.mode,
            circleCenter: cropEditor.circleCenter,
            circleRadius: cropEditor.circleRadius,
            freehandPoints: cropEditor.freehandPoints
        )
    }

    /// Start recording a drag operation (for debouncing)
    func beginDragOperation() {
        guard let cropEditor = cropEditor, let state = lastKnownState else { return }

        if !isRecordingDrag {
            isRecordingDrag = true
            pendingActionStart = CropUndoAction(
                type: .cropRectChange,
                previousCropRect: state.cropRect,
                previousMode: state.mode,
                previousCircleCenter: state.circleCenter,
                previousCircleRadius: state.circleRadius,
                previousFreehandPoints: state.freehandPoints,
                newCropRect: cropEditor.cropRect,
                newMode: cropEditor.mode,
                newCircleCenter: cropEditor.circleCenter,
                newCircleRadius: cropEditor.circleRadius,
                newFreehandPoints: cropEditor.freehandPoints
            )
        }

        // Reset debounce timer
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finalizeDragOperation()
            }
        }
    }

    /// Finalize a drag operation and create a single undo action
    private func finalizeDragOperation() {
        guard let cropEditor = cropEditor,
              let startState = pendingActionStart,
              isRecordingDrag else { return }

        isRecordingDrag = false
        pendingActionStart = nil
        debounceTimer?.invalidate()
        debounceTimer = nil

        // Create action with start state as previous and current state as new
        let action = CropUndoAction(
            type: startState.type,
            previousCropRect: startState.previousCropRect,
            previousMode: startState.previousMode,
            previousCircleCenter: startState.previousCircleCenter,
            previousCircleRadius: startState.previousCircleRadius,
            previousFreehandPoints: startState.previousFreehandPoints,
            newCropRect: cropEditor.cropRect,
            newMode: cropEditor.mode,
            newCircleCenter: cropEditor.circleCenter,
            newCircleRadius: cropEditor.circleRadius,
            newFreehandPoints: cropEditor.freehandPoints
        )

        pushAction(action)
        snapshotCurrentState()
    }

    /// Record an immediate action (not debounced)
    func recordAction(type: CropUndoAction.ActionType) {
        guard let cropEditor = cropEditor, let state = lastKnownState else { return }

        // Finalize any pending drag first
        if isRecordingDrag {
            finalizeDragOperation()
        }

        let action = CropUndoAction(
            type: type,
            previousCropRect: state.cropRect,
            previousMode: state.mode,
            previousCircleCenter: state.circleCenter,
            previousCircleRadius: state.circleRadius,
            previousFreehandPoints: state.freehandPoints,
            newCropRect: cropEditor.cropRect,
            newMode: cropEditor.mode,
            newCircleCenter: cropEditor.circleCenter,
            newCircleRadius: cropEditor.circleRadius,
            newFreehandPoints: cropEditor.freehandPoints
        )

        pushAction(action)
        snapshotCurrentState()
    }

    private func pushAction(_ action: CropUndoAction) {
        // Clear redo stack when new action is recorded
        redoStack.removeAll()
        undoStack.append(action)

        updateCanUndoRedo()
    }

    /// Undo the last action
    func undo() {
        guard let action = undoStack.popLast(), let cropEditor = cropEditor else { return }

        // Restore previous state
        cropEditor.cropRect = action.previousCropRect
        cropEditor.mode = action.previousMode
        cropEditor.circleCenter = action.previousCircleCenter
        cropEditor.circleRadius = action.previousCircleRadius
        cropEditor.freehandPoints = action.previousFreehandPoints

        redoStack.append(action)
        snapshotCurrentState()
        updateCanUndoRedo()
    }

    /// Redo the last undone action
    func redo() {
        guard let action = redoStack.popLast(), let cropEditor = cropEditor else { return }

        // Restore new state
        cropEditor.cropRect = action.newCropRect
        cropEditor.mode = action.newMode
        cropEditor.circleCenter = action.newCircleCenter
        cropEditor.circleRadius = action.newCircleRadius
        cropEditor.freehandPoints = action.newFreehandPoints

        undoStack.append(action)
        snapshotCurrentState()
        updateCanUndoRedo()
    }

    /// Clear all undo/redo history
    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        pendingActionStart = nil
        isRecordingDrag = false
        debounceTimer?.invalidate()
        debounceTimer = nil
        snapshotCurrentState()
        updateCanUndoRedo()
    }

    private func updateCanUndoRedo() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}

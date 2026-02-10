//
//  CropToolbarView.swift
//  cropaway
//
//  Main toolbar for crop editing with macOS 26 Liquid Glass styling.
//

import SwiftUI

struct CropToolbarView: View {
    @ObservedObject var video: VideoItem
    @ObservedObject var cropConfig: CropConfiguration

    @Environment(CropEditorViewModel.self) private var cropEditorVM: CropEditorViewModel
    @Environment(KeyframeViewModel.self) private var keyframeVM: KeyframeViewModel
    @Environment(TimelineViewModel.self) private var timelineVM: TimelineViewModel
    @EnvironmentObject var undoManager: CropUndoManager

    init(video: VideoItem) {
        self.video = video
        self.cropConfig = video.cropConfiguration
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main toolbar
            toolbarContent
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 52)
                .background(.bar)

            Divider()

            // AI sub-toolbar
            if cropEditorVM.mode == .ai {
                AIToolbarView(video: video)
                Divider()
            }
        }
    }

    private var toolbarContent: some View {
        HStack(spacing: 12) {
            cropModeButtons
            keyframeControls
            timelineControls

            Spacer()

            optionsSection

            Divider().frame(height: 20)

            editActions

            Divider().frame(height: 20)

            exportButton
        }
    }

    // MARK: - Crop Mode Buttons

    private var cropModeButtons: some View {
        HStack(spacing: 2) {
            ForEach(Array(CropMode.allCases.enumerated()), id: \.element.id) { index, mode in
                let isSelected = cropEditorVM.mode == mode
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        cropEditorVM.mode = mode
                    }
                } label: {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(width: 36, height: 32)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.borderless)
                .liquidGlassButton(isSelected: isSelected)
                .help("\(mode.displayName) (⌘\(index + 1))")
            }
        }
    }

    // MARK: - Keyframe Controls

    private var keyframeControls: some View {
        HStack(spacing: 4) {
            Button {
                if !cropConfig.preserveWidth {
                    cropConfig.preserveWidth = true
                }
                withAnimation(.snappy(duration: 0.2)) {
                    keyframeVM.keyframesEnabled.toggle()
                }
                if keyframeVM.keyframesEnabled && keyframeVM.keyframes.isEmpty {
                    NotificationCenter.default.post(name: .addKeyframe, object: nil)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: keyframeVM.keyframesEnabled ? "diamond.fill" : "diamond")
                        .font(.system(size: 11))
                        .contentTransition(.symbolEffect(.replace))
                    Text("Keyframes")
                        .font(.system(size: 11, weight: keyframeVM.keyframesEnabled ? .medium : .regular))
                }
                .foregroundStyle(keyframeVM.keyframesEnabled ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(Capsule())
            }
            .buttonStyle(.borderless)
            .liquidGlassCapsule(isSelected: keyframeVM.keyframesEnabled)
            .help("Toggle keyframe animation")

            if keyframeVM.keyframesEnabled {
                Button {
                    NotificationCenter.default.post(name: .addKeyframe, object: nil)
                } label: {
                    Image(systemName: "plus.diamond")
                        .font(.system(size: 12))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .liquidGlassCircle()
                .transition(.scale.combined(with: .opacity))
                .help("Add keyframe (⌘K)")
            }
        }
    }
    
    // MARK: - Timeline Controls
    
    private var timelineControls: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                timelineVM.toggleTimelinePanel(startingWith: video)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: timelineVM.isTimelinePanelVisible ? "film.fill" : "film")
                    .font(.system(size: 11))
                    .contentTransition(.symbolEffect(.replace))
                Text("Timeline")
                    .font(.system(size: 11, weight: timelineVM.isTimelinePanelVisible ? .medium : .regular))
            }
            .foregroundStyle(timelineVM.isTimelinePanelVisible ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .liquidGlassCapsule(isSelected: timelineVM.isTimelinePanelVisible)
        .help("Toggle timeline panel (⌘5)")
    }

    // MARK: - Options Section

    private var optionsSection: some View {
        HStack(spacing: 2) {
            Group {
                Button {
                    cropConfig.preserveWidth.toggle()
                    if !cropConfig.preserveWidth {
                        keyframeVM.keyframesEnabled = false
                        cropConfig.enableAlphaChannel = false
                    }
                } label: {
                    Image(systemName: cropConfig.preserveWidth ? "lock.fill" : "lock.open")
                        .font(.system(size: 12))
                        .foregroundStyle(cropConfig.preserveWidth ? Color.white : Color.primary)
                        .frame(width: 32, height: 32)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.borderless)
                .liquidGlassButton(isSelected: cropConfig.preserveWidth)
                .disabled(keyframeVM.keyframesEnabled || cropConfig.enableAlphaChannel)
                .opacity((keyframeVM.keyframesEnabled || cropConfig.enableAlphaChannel) ? 0.4 : 1.0)
            }
            .help("Preserve Size - Keep original dimensions")

            Group {
                Button {
                    if !cropConfig.preserveWidth { cropConfig.preserveWidth = true }
                    cropConfig.enableAlphaChannel.toggle()
                } label: {
                    Image(systemName: cropConfig.enableAlphaChannel ? "checkerboard.rectangle" : "rectangle")
                        .font(.system(size: 12))
                        .foregroundStyle(cropConfig.enableAlphaChannel ? Color.white : Color.primary)
                        .frame(width: 32, height: 32)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.borderless)
                .liquidGlassButton(isSelected: cropConfig.enableAlphaChannel)
                .disabled(!cropConfig.preserveWidth)
                .opacity(cropConfig.preserveWidth ? 1.0 : 0.4)
            }
            .help("Alpha - Export with transparency")
        }
    }

    // MARK: - Edit Actions

    private var editActions: some View {
        HStack(spacing: 2) {
            Button {
                NotificationCenter.default.post(name: .undoCrop, object: nil)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12))
                    .frame(width: 32, height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.borderless)
            .liquidGlassButton()
            .disabled(!undoManager.canUndo)
            .opacity(undoManager.canUndo ? 1.0 : 0.4)
            .help("Undo (⌘Z)")

            Button {
                NotificationCenter.default.post(name: .redoCrop, object: nil)
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 12))
                    .frame(width: 32, height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.borderless)
            .liquidGlassButton()
            .disabled(!undoManager.canRedo)
            .opacity(undoManager.canRedo ? 1.0 : 0.4)
            .help("Redo (⇧⌘Z)")

            Button {
                NotificationCenter.default.post(name: .resetCrop, object: nil)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .frame(width: 32, height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.borderless)
            .liquidGlassButton()
            .help("Reset (⇧⌘R)")
        }
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Menu {
            Button {
                NotificationCenter.default.post(name: .exportVideo, object: nil)
            } label: {
                Label("Export Video...", systemImage: "film")
            }

            Divider()

            Button {
                NotificationCenter.default.post(name: .exportJSON, object: nil)
            } label: {
                Label("Export Crop Data (JSON)...", systemImage: "doc.text")
            }

            Button {
                NotificationCenter.default.post(name: .exportBoundingBox, object: nil)
            } label: {
                Label("Export Bounding Boxes...", systemImage: "rectangle.dashed")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
                Text("Export")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(cropConfig.hasCropChanges ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
        } primaryAction: {
            NotificationCenter.default.post(name: .exportVideo, object: nil)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(height: 32)
        .liquidGlassCapsule(isSelected: cropConfig.hasCropChanges, tint: .accentColor)
        .disabled(!cropConfig.hasCropChanges)
        .help(cropConfig.hasCropChanges ? "Export video (⌘E)" : "Make changes to enable export")
    }
}

// MARK: - Liquid Glass Modifiers (with fallback for older macOS)

extension View {
    @ViewBuilder
    func liquidGlassButton(isSelected: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: 8)
            )
        } else {
            self.background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    func liquidGlassCapsule(isSelected: Bool = false, tint: Color = .accentColor) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                isSelected ? .regular.tint(tint).interactive() : .regular.interactive(),
                in: .capsule
            )
        } else {
            self.background(
                Capsule()
                    .fill(isSelected ? tint.opacity(0.2) : Color.primary.opacity(0.05))
            )
            .contentShape(Capsule())
        }
    }

    @ViewBuilder
    func liquidGlassCircle() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.background(
                Circle()
                    .fill(Color.primary.opacity(0.05))
            )
            .contentShape(Circle())
        }
    }

}

#Preview {
    struct PreviewWrapper: View {
        @StateObject var video = VideoItem(sourceURL: URL(fileURLWithPath: "/test.mov"))
        var body: some View {
            VStack {
                CropToolbarView(video: video)
                    .environment(CropEditorViewModel())
                    .environment(KeyframeViewModel())
                    .environmentObject(CropUndoManager())
                Spacer()
            }
            .frame(width: 900, height: 400)
            .background(Color.black)
        }
    }
    return PreviewWrapper()
}

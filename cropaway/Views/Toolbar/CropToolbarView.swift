//
//  CropToolbarView.swift
//  cropaway
//

import SwiftUI

struct CropToolbarView: View {
    @ObservedObject var video: VideoItem

    @EnvironmentObject var cropEditorVM: CropEditorViewModel
    @EnvironmentObject var keyframeVM: KeyframeViewModel
    @EnvironmentObject var undoManager: CropUndoManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Crop mode buttons - like Preview.app markup tools
                HStack(spacing: 2) {
                    ForEach(Array(CropMode.allCases.enumerated()), id: \.element.id) { index, mode in
                        Button {
                            cropEditorVM.mode = mode
                        } label: {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 13))
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(ToolbarButtonStyle(isSelected: cropEditorVM.mode == mode))
                        .help("\(mode.displayName) (\u{2318}\(index + 1))")
                    }
                }
                .padding(3)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Divider()
                    .frame(height: 20)

                // Keyframes toggle - only available when Preserve Size is enabled
                Button {
                    if !video.cropConfiguration.preserveWidth {
                        // Auto-enable preserve size when enabling keyframes
                        video.cropConfiguration.preserveWidth = true
                    }
                    let wasEnabled = keyframeVM.keyframesEnabled
                    withAnimation(.easeInOut(duration: 0.2)) {
                        keyframeVM.keyframesEnabled.toggle()
                    }
                    // Auto-create first keyframe when enabling keyframes
                    if !wasEnabled && keyframeVM.keyframesEnabled {
                        NotificationCenter.default.post(name: .addKeyframe, object: nil)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "diamond")
                            .font(.system(size: 11))
                        Text("Keyframes")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(ToolbarButtonStyle(isSelected: keyframeVM.keyframesEnabled))
                .disabled(!video.cropConfiguration.preserveWidth && !keyframeVM.keyframesEnabled)
                .opacity(video.cropConfiguration.preserveWidth || keyframeVM.keyframesEnabled ? 1.0 : 0.5)
                .help(video.cropConfiguration.preserveWidth ? "Toggle keyframe animation (\u{2318}K to add)" : "Keyframes require Preserve Size to be enabled")

                // Add keyframe button when keyframes are enabled
                if keyframeVM.keyframesEnabled {
                    Button {
                        NotificationCenter.default.post(name: .addKeyframe, object: nil)
                    } label: {
                        Image(systemName: "plus.diamond")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("Add keyframe at current time (\u{2318}K)")
                }

                Spacer()

                // Options - per-video settings
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { video.cropConfiguration.preserveWidth },
                        set: { newValue in
                            video.cropConfiguration.preserveWidth = newValue
                            // If preserve size is disabled, disable keyframes
                            if !newValue && keyframeVM.keyframesEnabled {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    keyframeVM.keyframesEnabled = false
                                }
                            }
                        }
                    )) {
                        Text("Preserve Size")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .help(keyframeVM.keyframesEnabled ? "Required for keyframe animation" : "Keep original dimensions, black fill outside crop")
                    .disabled(keyframeVM.keyframesEnabled) // Can't disable while keyframes active

                    Toggle(isOn: Binding(
                        get: { video.cropConfiguration.enableAlphaChannel },
                        set: { video.cropConfiguration.enableAlphaChannel = $0 }
                    )) {
                        Text("Alpha")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .help("Export with transparency (ProRes 4444)")
                }

                Divider()
                    .frame(height: 20)

                // Undo/Redo buttons
                HStack(spacing: 2) {
                    Button {
                        NotificationCenter.default.post(name: .undoCrop, object: nil)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!undoManager.canUndo)
                    .help("Undo (\u{2318}Z)")

                    Button {
                        NotificationCenter.default.post(name: .redoCrop, object: nil)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!undoManager.canRedo)
                    .help("Redo (\u{21E7}\u{2318}Z)")
                }

                Divider()
                    .frame(height: 20)

                // Reset
                Button {
                    NotificationCenter.default.post(name: .resetCrop, object: nil)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Reset crop (\u{21E7}\u{2318}R)")

                // Export menu with primary action
                Menu {
                    Button {
                        NotificationCenter.default.post(name: .exportVideo, object: nil)
                    } label: {
                        Label("Export Video...", systemImage: "film")
                    }
                    .keyboardShortcut("e", modifiers: .command)

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
                    Label("Export", systemImage: "square.and.arrow.up")
                        .labelStyle(.titleOnly)
                } primaryAction: {
                    NotificationCenter.default.post(name: .exportVideo, object: nil)
                }
                .menuStyle(.borderedButton)
                .fixedSize()
                .disabled(!video.hasCropChanges)
                .help(video.hasCropChanges ? "Export video (\u{2318}E) • Click arrow for more options" : "Make crop changes to enable export")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 44)

            Divider()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.1) : Color.clear)
            )
    }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject var video = VideoItem(sourceURL: URL(fileURLWithPath: "/test.mov"))
        var body: some View {
            CropToolbarView(video: video)
                .environmentObject(CropEditorViewModel())
                .environmentObject(KeyframeViewModel())
                .environmentObject(CropUndoManager())
                .frame(width: 800)
        }
    }
    return PreviewWrapper()
}

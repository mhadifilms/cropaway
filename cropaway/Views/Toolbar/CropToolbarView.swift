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

    @EnvironmentObject var cropEditorVM: CropEditorViewModel
    @EnvironmentObject var keyframeVM: KeyframeViewModel
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

            maskAdjustmentsToolbar

            // AI sub-toolbar
            if cropEditorVM.mode == .ai {
                Divider()
                AIToolbarView(video: video)
                Divider()
            }
        }
    }

    private var toolbarContent: some View {
        HStack(spacing: 12) {
            cropModeButtons
            keyframeControls

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

    // MARK: - Options Section

    private var optionsSection: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { cropConfig.preserveWidth },
                set: { newValue in
                    cropConfig.preserveWidth = newValue
                    if !newValue {
                        keyframeVM.keyframesEnabled = false
                        cropConfig.enableAlphaChannel = false
                    }
                }
            )) {
                Text("Preserve Size")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .disabled(keyframeVM.keyframesEnabled || cropConfig.enableAlphaChannel)
            .help("Keep original dimensions")

            Toggle(isOn: Binding(
                get: { cropConfig.enableAlphaChannel },
                set: { newValue in
                    if newValue { cropConfig.preserveWidth = true }
                    cropConfig.enableAlphaChannel = newValue
                }
            )) {
                Text("Alpha")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .disabled(!cropConfig.preserveWidth)
            .help("Export with transparency")
        }
    }

    // MARK: - Mask Adjustments

    private var maskAdjustmentsToolbar: some View {
        HStack(spacing: 14) {
            MaskAdjustmentSlider(
                title: "Smoothness",
                value: Binding(
                    get: { cropEditorVM.maskSmoothness },
                    set: { cropEditorVM.maskSmoothness = $0 }
                ),
                range: CropConfiguration.maskSmoothnessRange,
                step: 0.05
            )

            MaskAdjustmentSlider(
                title: "Radius",
                value: Binding(
                    get: { cropEditorVM.maskRadius },
                    set: { cropEditorVM.maskRadius = $0 }
                ),
                range: CropConfiguration.maskRadiusRange,
                step: 0.25
            )

            MaskAdjustmentSlider(
                title: "Denoise",
                value: Binding(
                    get: { cropEditorVM.maskDenoise },
                    set: { cropEditorVM.maskDenoise = $0 }
                ),
                range: CropConfiguration.maskDenoiseRange,
                step: 0.25
            )

            Spacer(minLength: 8)

            Button {
                cropEditorVM.maskSmoothness = 0
                cropEditorVM.maskRadius = 0
                cropEditorVM.maskDenoise = 0
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                    Text("Reset Mask")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Capsule())
            }
            .buttonStyle(.borderless)
            .liquidGlassCapsule()
            .disabled(!cropConfig.hasMaskAdjustments)
            .opacity(cropConfig.hasMaskAdjustments ? 1 : 0.45)
            .help("Reset mask smoothness, radius, and denoise")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 48)
        .background(.bar)
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
                NotificationCenter.default.post(name: .exportBoundingBox, object: nil)
            } label: {
                Label("Export Crop JSON...", systemImage: "rectangle.dashed")
            }

            Button {
                NotificationCenter.default.post(name: .exportBoundingBoxPickle, object: nil)
            } label: {
                Label("Export Crop Pickle...", systemImage: "rectangle.dashed.badge.record")
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

private struct MaskAdjustmentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Slider(value: $value, in: range, step: step)
                .frame(width: 120)

            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .liquidGlassCapsule()
    }
}

// MARK: - Liquid Glass Modifiers (with fallback for older macOS)

extension View {
    @ViewBuilder
    func liquidGlassButton(isSelected: Bool = false) -> some View {
        #if compiler(>=6.2)
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
        #else
        self.background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        #endif
    }

    @ViewBuilder
    func liquidGlassCapsule(isSelected: Bool = false, tint: Color = .accentColor) -> some View {
        #if compiler(>=6.2)
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
        #else
        self.background(
            Capsule()
                .fill(isSelected ? tint.opacity(0.2) : Color.primary.opacity(0.05))
        )
        .contentShape(Capsule())
        #endif
    }

    @ViewBuilder
    func liquidGlassCircle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.background(
                Circle()
                    .fill(Color.primary.opacity(0.05))
            )
            .contentShape(Circle())
        }
        #else
        self.background(
            Circle()
                .fill(Color.primary.opacity(0.05))
        )
        .contentShape(Circle())
        #endif
    }

}

#Preview {
    struct PreviewWrapper: View {
        @StateObject var video = VideoItem(sourceURL: URL(fileURLWithPath: "/test.mov"))
        var body: some View {
            VStack {
                CropToolbarView(video: video)
                    .environmentObject(CropEditorViewModel())
                    .environmentObject(KeyframeViewModel())
                    .environmentObject(CropUndoManager())
                Spacer()
            }
            .frame(width: 900, height: 400)
            .background(Color.black)
        }
    }
    return PreviewWrapper()
}

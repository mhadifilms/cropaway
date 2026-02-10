//
//  MaskRefinementPanelView.swift
//  cropaway
//

import SwiftUI

struct MaskRefinementPanelView: View {
    @ObservedObject var video: VideoItem

    @Environment(CropEditorViewModel.self) private var cropEditorVM: CropEditorViewModel
    @EnvironmentObject private var undoManager: CropUndoManager
    @ObservedObject private var presetStore = MaskRefinementPresetStore.shared

    @State private var draft: MaskRefinementParams = .default
    @State private var presetName: String = ""
    @State private var pendingCommit: DispatchWorkItem?

    private let debounceInterval: TimeInterval = 0.016

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                previewModePicker
                controls
                parameterSliders
                presetSection
            }
            .padding(14)
        }
        .scrollIndicators(.visible)
        .onAppear {
            draft = cropEditorVM.maskRefinement
        }
        .onChange(of: cropEditorVM.maskRefinement) { _, newValue in
            if newValue != draft {
                draft = newValue
            }
        }
        .onDisappear {
            pendingCommit?.cancel()
            pendingCommit = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mask Refinement")
                .font(.headline)

            Text(video.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var previewModePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Preview", selection: Binding(
                get: { cropEditorVM.showRefinedMaskPreview },
                set: { cropEditorVM.showRefinedMaskPreview = $0 }
            )) {
                Text("After").tag(true)
                Text("Before").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    applyAutoRefine()
                } label: {
                    Label("Auto Refine", systemImage: "wand.and.stars")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    setDraft(.default)
                } label: {
                    Label("Reset All", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            refinementPickerRow(
                title: "Morph",
                selection: Binding(
                    get: { draft.mode },
                    set: { value in
                        updateDraft { $0.mode = value }
                    }
                ),
                options: MorphMode.allCases
            ) { $0.displayName }

            refinementPickerRow(
                title: "Shape",
                selection: Binding(
                    get: { draft.shape },
                    set: { value in
                        updateDraft { $0.shape = value }
                    }
                ),
                options: KernelShape.allCases
            ) { $0.displayName }

            refinementPickerRow(
                title: "Quality",
                selection: Binding(
                    get: { draft.quality },
                    set: { value in
                        updateDraft { $0.quality = value }
                    }
                ),
                options: Quality.allCases
            ) { $0.displayName }
        }
    }

    private var parameterSliders: some View {
        VStack(spacing: 12) {
            intSliderRow(
                title: "Radius",
                value: draft.radius,
                range: 0...100,
                defaultValue: MaskRefinementParams.default.radius
            ) { value in
                updateDraft { $0.radius = value }
            } onReset: {
                updateDraft { $0.radius = MaskRefinementParams.default.radius }
            }

            intSliderRow(
                title: "Iterations",
                value: draft.iterations,
                range: 1...50,
                defaultValue: MaskRefinementParams.default.iterations
            ) { value in
                updateDraft { $0.iterations = value }
            } onReset: {
                updateDraft { $0.iterations = MaskRefinementParams.default.iterations }
            }

            doubleSliderRow(
                title: "Smoothing",
                value: draft.smoothing,
                range: 0...20,
                step: 0.1,
                defaultValue: MaskRefinementParams.default.smoothing,
                valueText: String(format: "%.1f", draft.smoothing)
            ) { value in
                updateDraft { $0.smoothing = value }
            } onReset: {
                updateDraft { $0.smoothing = MaskRefinementParams.default.smoothing }
            }

            doubleSliderRow(
                title: "Denoise",
                value: draft.denoise,
                range: 0...100,
                step: 1,
                defaultValue: MaskRefinementParams.default.denoise,
                valueText: String(format: "%.0f", draft.denoise)
            ) { value in
                updateDraft { $0.denoise = value }
            } onReset: {
                updateDraft { $0.denoise = MaskRefinementParams.default.denoise }
            }

            doubleSliderRow(
                title: "Blur Radius",
                value: draft.blurRadius,
                range: 0...200,
                step: 0.5,
                defaultValue: MaskRefinementParams.default.blurRadius,
                valueText: String(format: "%.1f px", draft.blurRadius)
            ) { value in
                updateDraft { $0.blurRadius = value }
            } onReset: {
                updateDraft { $0.blurRadius = MaskRefinementParams.default.blurRadius }
            }

            doubleSliderRow(
                title: "In/Out Ratio",
                value: draft.inOutRatio,
                range: -1...1,
                step: 0.01,
                defaultValue: MaskRefinementParams.default.inOutRatio,
                valueText: String(format: "%.2f", draft.inOutRatio)
            ) { value in
                updateDraft { $0.inOutRatio = value }
            } onReset: {
                updateDraft { $0.inOutRatio = MaskRefinementParams.default.inOutRatio }
            }

            doubleSliderRow(
                title: "Clean Black",
                value: draft.cleanBlack,
                range: 0...50,
                step: 0.5,
                defaultValue: MaskRefinementParams.default.cleanBlack,
                valueText: String(format: "%.1f", draft.cleanBlack)
            ) { value in
                updateDraft { $0.cleanBlack = value }
            } onReset: {
                updateDraft { $0.cleanBlack = MaskRefinementParams.default.cleanBlack }
            }

            doubleSliderRow(
                title: "Clean White",
                value: draft.cleanWhite,
                range: 0...50,
                step: 0.5,
                defaultValue: MaskRefinementParams.default.cleanWhite,
                valueText: String(format: "%.1f", draft.cleanWhite)
            ) { value in
                updateDraft { $0.cleanWhite = value }
            } onReset: {
                updateDraft { $0.cleanWhite = MaskRefinementParams.default.cleanWhite }
            }

            doubleSliderRow(
                title: "Black Clip",
                value: draft.blackClip,
                range: 0...100,
                step: 0.5,
                defaultValue: MaskRefinementParams.default.blackClip,
                valueText: String(format: "%.1f%%", draft.blackClip)
            ) { value in
                updateDraft { $0.blackClip = value }
            } onReset: {
                updateDraft { $0.blackClip = MaskRefinementParams.default.blackClip }
            }

            doubleSliderRow(
                title: "White Clip",
                value: draft.whiteClip,
                range: 0...100,
                step: 0.5,
                defaultValue: MaskRefinementParams.default.whiteClip,
                valueText: String(format: "%.1f%%", draft.whiteClip)
            ) { value in
                updateDraft { $0.whiteClip = value }
            } onReset: {
                updateDraft { $0.whiteClip = MaskRefinementParams.default.whiteClip }
            }

            doubleSliderRow(
                title: "Post Filter",
                value: draft.postFilter,
                range: 0...50,
                step: 0.5,
                defaultValue: MaskRefinementParams.default.postFilter,
                valueText: String(format: "%.1f", draft.postFilter)
            ) { value in
                updateDraft { $0.postFilter = value }
            } onReset: {
                updateDraft { $0.postFilter = MaskRefinementParams.default.postFilter }
            }

            doubleSliderRow(
                title: "Smart Refine",
                value: draft.smartRefine,
                range: 0...100,
                step: 1,
                defaultValue: MaskRefinementParams.default.smartRefine,
                valueText: String(format: "%.0f", draft.smartRefine)
            ) { value in
                updateDraft { $0.smartRefine = value }
            } onReset: {
                updateDraft { $0.smartRefine = MaskRefinementParams.default.smartRefine }
            }
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    savePreset()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Menu {
                if presetStore.presets.isEmpty {
                    Text("No presets saved")
                } else {
                    ForEach(presetStore.presets) { preset in
                        Button(preset.name) {
                            setDraft(preset.params)
                        }
                    }

                    Divider()

                    ForEach(presetStore.presets) { preset in
                        Button("Delete \(preset.name)", role: .destructive) {
                            presetStore.deletePreset(preset)
                        }
                    }
                }
            } label: {
                Label("Load Preset", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func savePreset() {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Preset \(presetStore.presets.count + 1)" : trimmed
        presetStore.savePreset(name: finalName, params: draft)
        presetName = ""
    }

    private func applyAutoRefine() {
        setDraft(.automated(for: cropEditorVM.mode))
    }

    private func setDraft(_ params: MaskRefinementParams) {
        undoManager.beginDragOperation()
        draft = params
        draft.sanitize()
        queueCommit()
    }

    private func updateDraft(_ update: (inout MaskRefinementParams) -> Void) {
        undoManager.beginDragOperation()
        update(&draft)
        draft.sanitize()
        queueCommit()
    }

    private func queueCommit() {
        pendingCommit?.cancel()
        let value = draft

        let work = DispatchWorkItem {
            cropEditorVM.maskRefinement = value
            cropEditorVM.notifyCropEditEnded()
        }

        pendingCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func refinementPickerRow<T: Hashable & Identifiable>(
        title: String,
        selection: Binding<T>,
        options: [T],
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func intSliderRow(
        title: String,
        value: Int,
        range: ClosedRange<Int>,
        defaultValue: Int,
        onChange: @escaping (Int) -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(value)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(value == defaultValue ? .tertiary : .secondary)
                .disabled(value == defaultValue)
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
        }
    }

    private func doubleSliderRow(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        defaultValue: Double,
        valueText: String,
        onChange: @escaping (Double) -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(abs(value - defaultValue) < 0.0001 ? .tertiary : .secondary)
                .disabled(abs(value - defaultValue) < 0.0001)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range,
                step: step
            )
        }
    }
}

#Preview {
    let video = VideoItem(sourceURL: URL(fileURLWithPath: "/tmp/preview.mov"))

    return MaskRefinementPanelView(video: video)
        .environment(CropEditorViewModel())
        .environmentObject(CropUndoManager())
        .frame(width: 320, height: 900)
}

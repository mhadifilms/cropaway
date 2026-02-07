//
//  AIToolbarView.swift
//  cropaway
//
//  Secondary toolbar for AI video tracking with macOS 26 Liquid Glass styling.
//

import SwiftUI

struct AIToolbarView: View {
    let video: VideoItem

    @EnvironmentObject var cropEditorVM: CropEditorViewModel
    @EnvironmentObject var keyframeVM: KeyframeViewModel
    @ObservedObject var falAIService = FalAIService.shared

    @State private var showingSetup = false
    @State private var textPrompt: String = ""
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        HStack(spacing: 12) {
            if !falAIService.hasAPIKey {
                setupRequiredView
            } else if falAIService.isProcessing {
                processingView
            } else {
                aiControlsView
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 48)
        .background(.bar)
        .sheet(isPresented: $showingSetup) {
            FalAISetupView()
        }
        .alert("AI Tracking Error", isPresented: $showError) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .onChange(of: errorMessage) { _, newValue in
            showError = newValue != nil
        }
    }

    // MARK: - Setup Required View

    private var setupRequiredView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                Text("API key required")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .liquidGlassCapsule()

            Spacer()

            Button {
                showingSetup = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "key")
                        .font(.system(size: 11))
                    Text("Configure fal.ai")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .contentShape(Capsule())
            }
            .buttonStyle(.borderless)
            .liquidGlassCapsule(isSelected: true)
            .help("Set up fal.ai API key for AI tracking")
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                statusText
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .liquidGlassCapsule()

            Spacer()

            Button {
                falAIService.cancelTracking()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(Capsule())
            }
            .buttonStyle(.borderless)
            .liquidGlassCapsule(isSelected: true, tint: .red)
            .help("Cancel AI tracking operation")
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch falAIService.status {
        case .uploading(let progress):
            Text("Uploading \(Int(progress * 100))%")
        case .processing(let progress):
            Text(progress > 0 ? "Tracking \(Int(progress * 100))%" : "Processing...")
        case .downloading:
            Text("Downloading...")
        case .extracting:
            Text("Extracting...")
        default:
            Text("Processing...")
        }
    }

    // MARK: - AI Controls View

    private var aiControlsView: some View {
        HStack(spacing: 12) {
            modePicker

            switch cropEditorVM.aiInteractionMode {
            case .text:
                textModeControls
            case .point:
                pointModeControls
            }

            Spacer()

            actionButtons
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(AIInteractionMode.allCases) { mode in
                let isSelected = cropEditorVM.aiInteractionMode == mode
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        cropEditorVM.aiInteractionMode = mode
                    }
                    // Clear state when switching modes (keep results if any)
                    if mode == .text {
                        cropEditorVM.aiPromptPoints = []
                    } else {
                        textPrompt = ""
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 11))
                        Text(mode.displayName)
                            .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
                .liquidGlassCapsule(isSelected: isSelected)
                .help(mode == .text ? "Track by text description" : "Track by clicking on object")
            }
        }
    }

    // MARK: - Text Mode Controls

    private var textModeControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                TextField("Object to track (person, car...)", text: $textPrompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 180)
                    .onSubmit {
                        submitTrackingRequest()
                    }

                if !textPrompt.isEmpty {
                    Button {
                        textPrompt = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear text prompt")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .liquidGlassCapsule()

            trackButton
                .disabled(textPrompt.isEmpty)
                .opacity(textPrompt.isEmpty ? 0.5 : 1.0)
        }
    }

    // MARK: - Point Mode Controls

    private var pointModeControls: some View {
        HStack(spacing: 8) {
            if !cropEditorVM.aiPromptPoints.isEmpty {
                // Point selected - show ready state
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("Point selected")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .liquidGlassCapsule()

                trackButton
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 11))
                    Text("Click on the object to track")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .liquidGlassCapsule()
            }
        }
    }

    // MARK: - Track Button

    private var trackButton: some View {
        Button {
            submitTrackingRequest()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "location.fill")
                    .font(.system(size: 10))
                Text("Track")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .liquidGlassCapsule(isSelected: true)
        .help("Track object across video frames")
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    cropEditorVM.clearAIMask()
                    textPrompt = ""
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .liquidGlassCircle()
            .disabled(!hasContent)
            .opacity(hasContent ? 1.0 : 0.4)
            .help("Clear selection")

            Button {
                showingSetup = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .liquidGlassCircle()
            .help("API Settings")
        }
    }

    private var hasContent: Bool {
        cropEditorVM.aiMaskData != nil ||
        !cropEditorVM.aiPromptPoints.isEmpty ||
        cropEditorVM.aiBoundingBox.width > 0 ||
        !textPrompt.isEmpty
    }

    // MARK: - Actions

    private func submitTrackingRequest() {
        // Validate based on mode
        if cropEditorVM.aiInteractionMode == .text {
            // Text mode requires a text prompt
            if textPrompt.isEmpty {
                errorMessage = "Please enter a description of the object to track."
                return
            }
        } else {
            // Point mode requires a point selection
            guard !cropEditorVM.aiPromptPoints.isEmpty else {
                errorMessage = "Please click on the object to track."
                return
            }
        }

        Task {
            await performVideoTracking()
        }
    }

    private func performVideoTracking() async {
        cropEditorVM.aiTextPrompt = textPrompt

        do {
            let frameRate = video.metadata.frameRate > 0 ? video.metadata.frameRate : 30.0

            // Determine what to send based on mode
            let promptToSend: String?
            let pointToSend: CGPoint?

            if cropEditorVM.aiInteractionMode == .text {
                // Text mode: use text prompt only
                promptToSend = textPrompt
                pointToSend = nil
            } else {
                // Point mode: use clicked point for tracking
                promptToSend = nil
                pointToSend = cropEditorVM.aiPromptPoints.first?.position
            }

            let result = try await falAIService.trackObject(
                videoURL: video.sourceURL,
                prompt: promptToSend,
                pointPrompt: pointToSend,
                frameRate: frameRate
            )

            applyTrackingResult(result, frameRate: frameRate)

        } catch {
            if case FalAIError.cancelled = error {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func applyTrackingResult(_ result: TrackingResult, frameRate: Double) {
        guard !result.masks.isEmpty else {
            errorMessage = "No mask data returned. Try a different prompt."
            return
        }

        keyframeVM.keyframesEnabled = true
        keyframeVM.keyframes.removeAll()

        // Sample keyframes at regular intervals (max 100 keyframes)
        let frameInterval = max(1, result.frameCount / 100)
        let sortedFrameIndices = result.masks.keys.sorted()

        for (index, frameIndex) in sortedFrameIndices.enumerated() {
            let isFirst = index == 0
            let isLast = index == sortedFrameIndices.count - 1
            let isAtInterval = index % frameInterval == 0

            if isFirst || isLast || isAtInterval {
                guard let maskData = result.masks[frameIndex] else { continue }

                // Use bounding box if available (for crop rect positioning)
                let box = result.boundingBoxes[frameIndex] ?? CGRect(x: 0, y: 0, width: 1, height: 1)

                let keyframe = Keyframe(
                    timestamp: Double(frameIndex) / frameRate,
                    cropRect: box,
                    edgeInsets: EdgeInsets(),
                    circleCenter: CGPoint(x: box.midX, y: box.midY),
                    circleRadius: min(box.width, box.height) / 2
                )
                keyframe.aiMaskData = maskData
                keyframe.aiBoundingBox = box

                keyframeVM.keyframes.append(keyframe)
            }
        }

        keyframeVM.sortKeyframes()

        // Set initial state from first frame
        if let firstIndex = sortedFrameIndices.first {
            if let firstMask = result.masks[firstIndex] {
                cropEditorVM.aiMaskData = firstMask
                print("[FalAI] Set initial aiMaskData: \(firstMask.count) bytes")

                // Test decode immediately
                if let (_, w, h) = AIMaskResult.decodeMaskToImage(firstMask) {
                    print("[FalAI] Initial mask decoded successfully: \(w)x\(h)")
                } else {
                    print("[FalAI] WARNING: Initial mask failed to decode!")
                }
            }
            if let firstBox = result.boundingBoxes[firstIndex] {
                cropEditorVM.aiBoundingBox = firstBox
                cropEditorVM.cropRect = firstBox
                print("[FalAI] Set initial bounding box: \(firstBox)")
            }
        }

        print("[FalAI] Created \(keyframeVM.keyframes.count) keyframes with RLE masks")
        print("[FalAI] Current mode: \(cropEditorVM.mode)")
        cropEditorVM.notifyCropEditEnded()
    }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject var video = VideoItem(sourceURL: URL(fileURLWithPath: "/test.mov"))
        var body: some View {
            VStack {
                AIToolbarView(video: video)
                Spacer()
            }
            .environmentObject(CropEditorViewModel())
            .environmentObject(KeyframeViewModel())
            .frame(width: 800, height: 400)
            .background(Color.black)
        }
    }
    return PreviewWrapper()
}

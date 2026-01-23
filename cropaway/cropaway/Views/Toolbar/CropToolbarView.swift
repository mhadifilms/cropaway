//
//  CropToolbarView.swift
//  cropaway
//

import SwiftUI

struct CropToolbarView: View {
    @ObservedObject var video: VideoItem
    @ObservedObject var cropConfig: CropConfiguration

    @EnvironmentObject var cropEditorVM: CropEditorViewModel
    @EnvironmentObject var keyframeVM: KeyframeViewModel
    @EnvironmentObject var undoManager: CropUndoManager

    @StateObject private var sam3Service = SAM3Service.shared
    @State private var showingSAM3Setup = false

    init(video: VideoItem) {
        self.video = video
        self.cropConfig = video.cropConfiguration
    }

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

                // AI Mode controls
                if cropEditorVM.mode == .ai {
                    Divider()
                        .frame(height: 20)

                    AIToolbarControls(
                        sam3Service: sam3Service,
                        showingSAM3Setup: $showingSAM3Setup
                    )
                }

                Divider()
                    .frame(height: 20)

                // Keyframes toggle - only available when Preserve Size is enabled
                Button {
                    if !cropConfig.preserveWidth {
                        // Auto-enable preserve size when enabling keyframes
                        cropConfig.preserveWidth = true
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
                .disabled(!cropConfig.preserveWidth && !keyframeVM.keyframesEnabled)
                .opacity(cropConfig.preserveWidth || keyframeVM.keyframesEnabled ? 1.0 : 0.5)
                .help(cropConfig.preserveWidth ? "Toggle keyframe animation (\u{2318}K to add)" : "Keyframes require Preserve Size to be enabled")

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
                    Toggle(isOn: $cropConfig.preserveWidth) {
                        Text("Preserve Size")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .help(keyframeVM.keyframesEnabled ? "Required for keyframes & alpha" : "Keep original dimensions, required for alpha channel")
                    .disabled(keyframeVM.keyframesEnabled || cropConfig.enableAlphaChannel)
                    .onChange(of: cropConfig.preserveWidth) { _, newValue in
                        if !newValue {
                            // Disable keyframes and alpha when preserve size is off
                            if keyframeVM.keyframesEnabled {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    keyframeVM.keyframesEnabled = false
                                }
                            }
                            if cropConfig.enableAlphaChannel {
                                cropConfig.enableAlphaChannel = false
                            }
                        }
                    }

                    Toggle(isOn: $cropConfig.enableAlphaChannel) {
                        Text("Alpha")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .help(cropConfig.preserveWidth ? "Export with transparency (ProRes 4444)" : "Requires Preserve Size to be enabled")
                    .disabled(!cropConfig.preserveWidth)
                    .onChange(of: cropConfig.enableAlphaChannel) { _, newValue in
                        // Auto-enable preserve size when enabling alpha
                        if newValue && !cropConfig.preserveWidth {
                            cropConfig.preserveWidth = true
                        }
                    }
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
                .disabled(!cropConfig.hasCropChanges)
                .help(cropConfig.hasCropChanges ? "Export video (\u{2318}E) • Click arrow for more options" : "Make crop changes to enable export")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 44)

            Divider()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingSAM3Setup) {
            SAM3SetupView()
        }
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

/// AI-specific toolbar controls
struct AIToolbarControls: View {
    @ObservedObject var sam3Service: SAM3Service
    @Binding var showingSAM3Setup: Bool

    @EnvironmentObject var cropEditorVM: CropEditorViewModel

    private var isSetupComplete: Bool {
        UserDefaults.standard.bool(forKey: "SAM3SetupComplete")
    }

    var body: some View {
        HStack(spacing: 8) {
            // Server status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Setup button (if not set up)
            if !isSetupComplete {
                Button("Setup AI") {
                    showingSAM3Setup = true
                }
                .font(.system(size: 11))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            // Start/Stop server button (if set up)
            else if sam3Service.serverStatus == .stopped || isErrorState {
                Button("Start AI") {
                    Task {
                        do {
                            try await sam3Service.startServer()
                            try await sam3Service.initializeModel()
                        } catch {
                            print("SAM3 Error: \(error)")
                            // Show setup if it fails
                            if case .error = sam3Service.serverStatus {
                                showingSAM3Setup = true
                            }
                        }
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
            }

            // Settings gear button
            if isSetupComplete {
                Button {
                    showingSAM3Setup = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("AI Setup")
            }

            // Clear points button
            if !cropEditorVM.aiPromptPoints.isEmpty {
                Button {
                    cropEditorVM.aiPromptPoints.removeAll()
                    cropEditorVM.aiMaskData = nil
                    cropEditorVM.aiBoundingBox = .zero
                    cropEditorVM.notifyCropEditEnded()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Clear")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderless)
                .help("Clear all prompt points")
            }

            // Processing indicator
            if sam3Service.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 4)
            }
        }
    }

    private var isErrorState: Bool {
        if case .error = sam3Service.serverStatus {
            return true
        }
        return false
    }

    private var statusColor: Color {
        switch sam3Service.serverStatus {
        case .stopped:
            return .gray
        case .starting:
            return .orange
        case .ready:
            return .green
        case .processing:
            return .blue
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch sam3Service.serverStatus {
        case .stopped:
            return "AI Off"
        case .starting:
            return "Starting..."
        case .ready:
            return "AI Ready"
        case .processing:
            return "Processing..."
        case .error(let msg):
            return msg.isEmpty ? "Error" : "Error: \(msg.prefix(20))"
        }
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

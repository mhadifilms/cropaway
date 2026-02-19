//
//  FalAISetupView.swift
//  cropaway
//
//  Setup view for fal.ai API key configuration.
//

import SwiftUI

struct FalAISetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var falAIService = FalAIService.shared

    @State private var apiKey: String = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var showSuccess = false
    @State private var showDeleteConfirm = false

    private var hasExistingKey: Bool {
        falAIService.hasAPIKey
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if hasExistingKey && apiKey.isEmpty {
                        existingKeySection
                    } else {
                        benefitsSection
                        Divider()
                        apiKeySection
                    }

                    // Status messages
                    statusMessages

                    // Pricing info
                    pricingSection
                }
                .padding(24)
            }

            Divider()

            // Footer
            footerSection
                .padding(16)
        }
        .frame(width: 480, height: hasExistingKey && apiKey.isEmpty ? 400 : 540)
        .onAppear {
            if !hasExistingKey {
                apiKey = ""
            }
        }
        .alert("Remove API Key", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                falAIService.removeAPIKey()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to remove your fal.ai API key? You'll need to enter it again to use AI tracking.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.blue)
            }

            Text("AI Video Tracking")
                .font(.title2.bold())

            Text("Powered by fal.ai SAM3")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Existing Key Section

    private var existingKeySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("API Key Configured")
                        .font(.headline)
                    Text("You're ready to use AI tracking")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(Color.green.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Actions
            VStack(alignment: .leading, spacing: 12) {
                Text("Options")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        apiKey = falAIService.apiKey ?? ""
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                            Text("Change Key")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .controlContainerGlassBackground(cornerRadius: 8)

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Remove Key")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .tintedGlassEffect(.red, cornerRadius: 8)
                }
            }
        }
    }

    // MARK: - Benefits Section

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Features")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                FeatureCard(icon: "film.stack", title: "Video Tracking", description: "Track objects across all frames")
                FeatureCard(icon: "cloud", title: "Cloud Processing", description: "No local GPU required")
                FeatureCard(icon: "bolt.fill", title: "Fast Results", description: "Optimized inference")
                FeatureCard(icon: "dollarsign.circle", title: "Pay Per Use", description: "~$0.005 per 16 frames")
            }
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("API Key")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Link(destination: URL(string: "https://fal.ai/dashboard/keys")!) {
                    HStack(spacing: 4) {
                        Text("Get API Key")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                }
            }

            // Custom styled text field
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                SecureField("Enter your fal.ai API key", text: $apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit {
                        saveAPIKey()
                    }

                if !apiKey.isEmpty {
                    Button {
                        apiKey = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            Text("Your API key is stored securely on your device and never shared.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Status Messages

    @ViewBuilder
    private var statusMessages: some View {
        if let error = validationError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.callout)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }

        if showSuccess {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("API key saved successfully")
                    .font(.callout)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Pricing Information")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }

            Text("SAM3 Video costs approximately $0.005 per 16 frames. A typical 10-second video at 30fps (300 frames) costs about $0.09.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineSpacing(2)

            Link(destination: URL(string: "https://fal.ai/models/fal-ai/sam-3/video")!) {
                Text("View full pricing details")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Spacer()

            if showSuccess {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(minWidth: 80)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            } else if !apiKey.isEmpty {
                Button {
                    saveAPIKey()
                } label: {
                    HStack(spacing: 6) {
                        if isValidating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isValidating ? "Validating..." : "Save API Key")
                    }
                    .frame(minWidth: 100)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty || isValidating)
            } else if hasExistingKey {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(minWidth: 80)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func saveAPIKey() {
        guard !apiKey.isEmpty else { return }

        validationError = nil
        showSuccess = false
        isValidating = true

        // Basic validation
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedKey.count < 20 {
            validationError = "API key is too short. Please check that you've entered the complete key."
            isValidating = false
            return
        }

        // Save the key
        falAIService.saveAPIKey(trimmedKey)
        apiKey = trimmedKey

        isValidating = false
        showSuccess = true
    }
}

// MARK: - Feature Card

private struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .featureCardGlassBackground()
    }
}

extension View {
    @ViewBuilder
    func featureCardGlassBackground() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        } else {
            self
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Preview

#Preview("No Key") {
    FalAISetupView()
}

#Preview("With Key") {
    let _ = FalAIService.shared.saveAPIKey("fal_test_key_12345678901234567890")
    return FalAISetupView()
}

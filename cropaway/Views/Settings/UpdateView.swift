//
//  UpdateView.swift
//  cropaway
//
//  Update dialog with download progress and release notes.
//

import SwiftUI

struct UpdateAvailableView: View {
    @ObservedObject var updateService = UpdateService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // Content based on status
            switch updateService.status {
            case .available(let version, let notes):
                availableContent(version: version, notes: notes)
            case .downloading(let progress):
                downloadingContent(progress: progress)
            case .readyToInstall:
                readyToInstallContent
            case .installing:
                installingContent
            case .error(let message):
                errorContent(message: message)
            default:
                EmptyView()
            }

            Divider()

            // Actions
            actionButtons
                .padding(16)
        }
        .frame(width: 480)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            // App icon
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("A new version of Cropaway is available!")
                    .font(.headline)

                if case .available(let version, _) = updateService.status {
                    Text("Version \(version) is now available — you have \(updateService.currentVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Available Content

    private func availableContent(version: String, notes: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Release Notes:")
                .font(.subheadline)
                .fontWeight(.medium)

            ScrollView {
                if let notes = notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    Text("No release notes available.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 150)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(24)
    }

    // MARK: - Downloading Content

    private func downloadingContent(progress: Double) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: progress) {
                Text("Downloading update...")
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
            }
            .progressViewStyle(.linear)

            Text("Please wait while the update is downloaded.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(height: 150)
    }

    // MARK: - Ready to Install Content

    private var readyToInstallContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Download Complete")
                .font(.headline)

            Text("Click \"Install and Relaunch\" to complete the update.\nCropaway will restart automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(height: 150)
    }

    // MARK: - Installing Content

    private var installingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Installing update...")
                .font(.headline)

            Text("Cropaway will restart momentarily.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(height: 150)
    }

    // MARK: - Error Content

    private func errorContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Update Error")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(height: 150)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            switch updateService.status {
            case .available:
                Button("Skip This Version") {
                    updateService.skipVersion()
                    dismiss()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Remind Me Later") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Download Update") {
                    Task {
                        try? await updateService.downloadUpdate()
                    }
                }
                .buttonStyle(.borderedProminent)

            case .downloading:
                Spacer()

                Button("Cancel") {
                    updateService.cancelDownload()
                    dismiss()
                }
                .buttonStyle(.bordered)

            case .readyToInstall:
                Button("View on GitHub") {
                    updateService.openReleasePage()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Later") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Install and Relaunch") {
                    Task {
                        try? await updateService.installUpdate()
                    }
                }
                .buttonStyle(.borderedProminent)

            case .installing:
                Spacer()
                // No buttons while installing

            case .error:
                Spacer()

                Button("Try Again") {
                    Task {
                        await updateService.checkForUpdates(force: true)
                    }
                }
                .buttonStyle(.bordered)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

            default:
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Update Check View (for menu bar)

struct UpdateCheckView: View {
    @ObservedObject var updateService = UpdateService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            switch updateService.status {
            case .checking:
                checkingView

            case .upToDate:
                upToDateView

            case .available(let version, _):
                updateAvailableView(version: version)

            case .error(let message):
                errorView(message: message)

            default:
                EmptyView()
            }
        }
        .frame(width: 300, height: 200)
        .padding(24)
        .background(.regularMaterial)
    }

    private var checkingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Checking for updates...")
                .font(.headline)
        }
    }

    private var upToDateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're up to date!")
                .font(.headline)

            Text("Cropaway \(updateService.currentVersion) is the latest version.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("OK") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func updateAvailableView(version: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Update Available")
                .font(.headline)

            Text("Version \(version) is available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Button("Later") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("View Update") {
                    dismiss()
                    // Show full update dialog
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .showUpdateDialog, object: nil)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Check Failed")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("OK") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let showUpdateDialog = Notification.Name("showUpdateDialog")
    static let checkForUpdates = Notification.Name("checkForUpdates")
}

#Preview("Update Available") {
    UpdateAvailableView()
}

#Preview("Check View") {
    UpdateCheckView()
}

//
//  UpdateService.swift
//  cropaway
//
//  Service for checking and installing app updates from GitHub Releases.
//

import Foundation
import AppKit
import Combine

/// Represents a GitHub release
struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String?
    let htmlUrl: String
    let publishedAt: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let size: Int
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadUrl = "browser_download_url"
    }
}

/// Update status
enum UpdateStatus: Equatable {
    case idle
    case checking
    case available(version: String, notes: String?)
    case downloading(progress: Double)
    case readyToInstall
    case installing
    case error(String)
    case upToDate

    static func == (lhs: UpdateStatus, rhs: UpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.readyToInstall, .readyToInstall),
             (.installing, .installing), (.upToDate, .upToDate):
            return true
        case (.available(let v1, _), .available(let v2, _)):
            return v1 == v2
        case (.downloading(let p1), .downloading(let p2)):
            return p1 == p2
        case (.error(let e1), .error(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

/// Errors from update service
enum UpdateError: LocalizedError {
    case networkError(String)
    case invalidResponse
    case noAssetFound
    case downloadFailed(String)
    case installFailed(String)
    case versionParseError

    var errorDescription: String? {
        switch self {
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidResponse:
            return "Invalid response from server"
        case .noAssetFound:
            return "No downloadable update found"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .installFailed(let msg):
            return "Installation failed: \(msg)"
        case .versionParseError:
            return "Could not parse version number"
        }
    }
}

/// Service for app updates via GitHub Releases
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var status: UpdateStatus = .idle
    @Published var latestRelease: GitHubRelease?
    @Published var downloadedDMGPath: URL?

    // GitHub repository info - update these for your repo
    private let owner = "mhadifilms"
    private let repo = "cropaway"

    private let session: URLSession
    private var downloadTask: URLSessionDownloadTask?

    // UserDefaults keys
    private let lastCheckKey = "UpdateLastCheckDate"
    private let skipVersionKey = "UpdateSkipVersion"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600 // 10 min for downloads
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// Current app version from bundle
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Current build number
    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// Check if enough time has passed since last check (24 hours)
    var shouldCheckAutomatically: Bool {
        guard let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) > 86400 // 24 hours
    }

    /// Version to skip (user chose "Skip This Version")
    var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: skipVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: skipVersionKey) }
    }

    /// Check for updates
    func checkForUpdates(force: Bool = false) async {
        guard status != .checking else { return }

        status = .checking

        do {
            let release = try await fetchLatestRelease()
            latestRelease = release

            // Save check time
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            // Compare versions
            let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")

            if isVersion(latestVersion, newerThan: currentVersion) {
                // Check if user skipped this version
                if !force && skippedVersion == latestVersion {
                    status = .upToDate
                    return
                }
                status = .available(version: latestVersion, notes: release.body)
            } else {
                status = .upToDate
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Download the update
    func downloadUpdate() async throws {
        guard let release = latestRelease else {
            throw UpdateError.noAssetFound
        }

        // Find DMG asset
        guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            throw UpdateError.noAssetFound
        }

        guard let downloadURL = URL(string: dmgAsset.browserDownloadUrl) else {
            throw UpdateError.invalidResponse
        }

        status = .downloading(progress: 0)

        // Download to temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent(dmgAsset.name)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: destURL)

        // Download with progress
        let (localURL, _) = try await downloadWithProgress(from: downloadURL)

        // Move to destination
        try FileManager.default.moveItem(at: localURL, to: destURL)

        downloadedDMGPath = destURL
        status = .readyToInstall
    }

    /// Install the downloaded update
    func installUpdate() async throws {
        guard let dmgPath = downloadedDMGPath else {
            throw UpdateError.installFailed("No downloaded update found")
        }

        status = .installing

        do {
            // Mount the DMG
            let mountPoint = try await mountDMG(at: dmgPath)

            defer {
                // Unmount when done
                Task {
                    try? await unmountDMG(at: mountPoint)
                }
            }

            // Find the .app in the mounted volume
            let appName = "Cropaway.app"
            let sourceApp = mountPoint.appendingPathComponent(appName)

            guard FileManager.default.fileExists(atPath: sourceApp.path) else {
                throw UpdateError.installFailed("Could not find \(appName) in update")
            }

            // Get current app location
            let currentAppURL = Bundle.main.bundleURL
            let applicationsURL = URL(fileURLWithPath: "/Applications/\(appName)")

            // Determine install location
            let installURL: URL
            if currentAppURL.path.hasPrefix("/Applications") {
                installURL = currentAppURL
            } else {
                installURL = applicationsURL
            }

            // Create update script that runs after app quits
            let scriptPath = try createUpdateScript(
                sourceApp: sourceApp,
                destApp: installURL,
                appToRelaunch: installURL
            )

            // Run the script
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            try process.run()

            // Quit the app - the script will handle the rest
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }

        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    /// Skip the current available version
    func skipVersion() {
        if case .available(let version, _) = status {
            skippedVersion = version
            status = .idle
        }
    }

    /// Cancel ongoing download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        status = .idle
    }

    /// Open release page in browser
    func openReleasePage() {
        guard let release = latestRelease,
              let url = URL(string: release.htmlUrl) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private Methods

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Cropaway/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw UpdateError.networkError("No releases found")
        }

        if httpResponse.statusCode != 200 {
            throw UpdateError.networkError("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    private func downloadWithProgress(from url: URL) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate { [weak self] progress in
                Task { @MainActor in
                    self?.status = .downloading(progress: progress)
                }
            }

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url) { localURL, response, error in
                if let error = error {
                    continuation.resume(throwing: UpdateError.downloadFailed(error.localizedDescription))
                    return
                }

                guard let localURL = localURL, let response = response else {
                    continuation.resume(throwing: UpdateError.downloadFailed("No data received"))
                    return
                }

                // Copy to a persistent location before the temp file is deleted
                let tempCopy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".dmg")
                do {
                    try FileManager.default.copyItem(at: localURL, to: tempCopy)
                    continuation.resume(returning: (tempCopy, response))
                } catch {
                    continuation.resume(throwing: UpdateError.downloadFailed(error.localizedDescription))
                }
            }

            self.downloadTask = task
            task.resume()
        }
    }

    private func mountDMG(at path: URL) async throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path.path, "-nobrowse", "-plist"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw UpdateError.installFailed("Failed to mount disk image")
        }

        // Find the mount point
        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return URL(fileURLWithPath: mountPoint)
            }
        }

        throw UpdateError.installFailed("Could not find mount point")
    }

    private func unmountDMG(at mountPoint: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-force"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
    }

    private func createUpdateScript(sourceApp: URL, destApp: URL, appToRelaunch: URL) throws -> String {
        let scriptContent = """
        #!/bin/bash
        # Wait for app to quit
        sleep 2

        # Remove old app
        rm -rf "\(destApp.path)"

        # Copy new app
        cp -R "\(sourceApp.path)" "\(destApp.path)"

        # Fix permissions
        chmod -R 755 "\(destApp.path)"
        xattr -cr "\(destApp.path)" 2>/dev/null || true

        # Relaunch
        open "\(appToRelaunch.path)"

        # Clean up this script
        rm -f "$0"
        """

        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("cropaway_update.sh")

        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath.path
        )

        return scriptPath.path
    }

    /// Compare semantic versions
    private func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let components1 = v1.split(separator: ".").compactMap { Int($0) }
        let components2 = v2.split(separator: ".").compactMap { Int($0) }

        // Pad with zeros
        let maxCount = max(components1.count, components2.count)
        var c1 = components1
        var c2 = components2

        while c1.count < maxCount { c1.append(0) }
        while c2.count < maxCount { c2.append(0) }

        for i in 0..<maxCount {
            if c1[i] > c2[i] { return true }
            if c1[i] < c2[i] { return false }
        }

        return false
    }
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void

    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Handled in completion handler
    }
}

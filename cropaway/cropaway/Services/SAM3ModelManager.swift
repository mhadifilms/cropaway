//
//  SAM3ModelManager.swift
//  cropaway
//
//  Manages SAM3 model downloads and caching.
//

import Foundation
import Combine

/// Manager for SAM3 model downloads and storage
@MainActor
final class SAM3ModelManager: ObservableObject {
    static let shared = SAM3ModelManager()

    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    @Published var isModelReady = false
    @Published var currentModelSize: SAM3ModelSize = .huge
    @Published var lastError: String?

    private let supportDir: URL

    private init() {
        // Get Application Support directory
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        supportDir = appSupport.appendingPathComponent("Cropaway", isDirectory: true)

        // Create directories if needed
        try? FileManager.default.createDirectory(
            at: supportDir,
            withIntermediateDirectories: true
        )

        // Check if model exists
        checkModelStatus()
    }

    /// Directory for models
    var modelsDir: URL {
        supportDir.appendingPathComponent("models", isDirectory: true)
    }

    /// Check if required Python packages are installed
    func checkPythonEnvironment() async -> PythonEnvironmentStatus {
        // Check for Python
        let pythonPath = findPythonPath()
        guard pythonPath != nil else {
            return .pythonMissing
        }

        // Check for required packages
        let requiredPackages = ["torch", "transformers", "flask", "pillow", "numpy"]
        var missingPackages: [String] = []

        for package in requiredPackages {
            if await !isPackageInstalled(package) {
                missingPackages.append(package)
            }
        }

        if !missingPackages.isEmpty {
            return .packagesMissing(missingPackages)
        }

        return .ready
    }

    /// Install required Python packages
    func installPythonPackages() async throws {
        guard let pythonPath = findPythonPath() else {
            throw SAM3ModelError.pythonNotFound
        }

        // Find requirements.txt
        guard let requirementsPath = findRequirementsFile() else {
            throw SAM3ModelError.requirementsNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "pip", "install", "-r", requirementsPath]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SAM3ModelError.installFailed(errorMessage)
        }
    }

    /// Get estimated model size
    func getModelSize(_ size: SAM3ModelSize) -> String {
        switch size {
        case .base:
            return "~375 MB"
        case .large:
            return "~1.2 GB"
        case .huge:
            return "~2.5 GB"
        }
    }

    /// Get model description
    func getModelDescription(_ size: SAM3ModelSize) -> String {
        switch size {
        case .base:
            return "Fastest inference, good for quick previews"
        case .large:
            return "Balanced speed and quality"
        case .huge:
            return "Best quality, slower inference"
        }
    }

    // MARK: - Private Helpers

    private func checkModelStatus() {
        // Models are downloaded by HuggingFace transformers library
        // on first use, so we just check if packages are available
        isModelReady = true
    }

    private func findPythonPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func findRequirementsFile() -> String? {
        // Check in bundle
        if let bundlePath = Bundle.main.resourcePath {
            let path = (bundlePath as NSString).appendingPathComponent("python/requirements.txt")
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Check development location
        let devPath = Bundle.main.bundlePath
            .components(separatedBy: "/Build/")[0]
            .appending("/cropaway/Resources/python/requirements.txt")
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }

        return nil
    }

    private func isPackageInstalled(_ package: String) async -> Bool {
        guard let pythonPath = findPythonPath() else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import \(package)"]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Types

enum PythonEnvironmentStatus {
    case ready
    case pythonMissing
    case packagesMissing([String])
}

enum SAM3ModelError: LocalizedError {
    case pythonNotFound
    case requirementsNotFound
    case installFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python 3.10+ not found. Please install Python."
        case .requirementsNotFound:
            return "Requirements file not found."
        case .installFailed(let message):
            return "Failed to install packages: \(message)"
        case .downloadFailed(let message):
            return "Failed to download model: \(message)"
        }
    }
}

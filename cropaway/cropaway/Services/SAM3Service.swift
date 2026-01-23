//
//  SAM3Service.swift
//  cropaway
//
//  Service for communicating with the SAM3 Python backend server.
//

import Foundation
import AppKit
import SwiftUI
import Combine

/// Response structure from SAM3 server
struct SAM3SegmentResponse: Codable {
    let status: String
    let mask: String?
    let boundingBox: BoundingBox?
    let confidence: Double?
    let objectId: String?
    let message: String?
    let hint: String?

    struct BoundingBox: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        var cgRect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    enum CodingKeys: String, CodingKey {
        case status, mask, confidence, message, hint
        case boundingBox = "bounding_box"
        case objectId = "object_id"
    }
}

/// Health check response
struct SAM3HealthResponse: Codable {
    let status: String
    let modelLoaded: Bool?
    let modelId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case modelLoaded = "model_loaded"
        case modelId = "model_id"
    }
}

/// Service for managing SAM3 Python server and making segmentation requests
@MainActor
final class SAM3Service: ObservableObject {
    static let shared = SAM3Service()

    @Published var serverStatus: SAM3ServerStatus = .stopped
    @Published var isProcessing = false
    @Published var lastError: String?

    private var serverProcess: Process?
    private let port = 8765
    private let host = "127.0.0.1"

    private var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120  // 2 minute timeout for inference
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Server Management

    /// Start the Python SAM3 server
    func startServer() async throws {
        guard serverStatus == .stopped || serverStatus == .error("") else {
            return
        }

        serverStatus = .starting

        // Find Python executable
        guard let pythonPath = findPythonExecutable() else {
            serverStatus = .error("Python not found. Please install Python 3.10+")
            throw SAM3Error.pythonNotFound
        }

        // Find server script
        guard let scriptPath = findServerScript() else {
            serverStatus = .error("SAM3 server script not found")
            throw SAM3Error.scriptNotFound
        }

        // Start process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, "--port", String(port), "--host", host]
        process.currentDirectoryURL = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()

        // Set up environment
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Log output
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("[SAM3 Server] \(output)")
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("[SAM3 Server Error] \(output)")
            }
        }

        do {
            try process.run()
            serverProcess = process

            // Wait for server to be ready
            for _ in 0..<30 {  // 30 second timeout
                try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                if await checkServerHealth() {
                    serverStatus = .ready
                    return
                }
            }

            serverStatus = .error("Server failed to start")
            throw SAM3Error.serverStartFailed

        } catch {
            serverStatus = .error(error.localizedDescription)
            throw error
        }
    }

    /// Stop the Python server
    func stopServer() {
        serverProcess?.terminate()
        serverProcess = nil
        serverStatus = .stopped
    }

    /// Check if server is healthy
    func checkServerHealth() async -> Bool {
        do {
            let url = baseURL.appendingPathComponent("health")
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            let health = try JSONDecoder().decode(SAM3HealthResponse.self, from: data)
            return health.status == "ok"
        } catch {
            return false
        }
    }

    // MARK: - Model Management

    /// Initialize/load the SAM model
    func initializeModel(modelId: String = "facebook/sam-vit-huge") async throws {
        serverStatus = .processing

        let url = baseURL.appendingPathComponent("initialize")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["model_id": modelId]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SAM3Error.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(SAM3SegmentResponse.self, from: data) {
                throw SAM3Error.serverError(errorResponse.message ?? "Unknown error")
            }
            throw SAM3Error.serverError("HTTP \(httpResponse.statusCode)")
        }

        serverStatus = .ready
    }

    /// Unload the model to free memory
    func unloadModel() async throws {
        let url = baseURL.appendingPathComponent("unload")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SAM3Error.invalidResponse
        }
    }

    // MARK: - Segmentation

    /// Segment image with point prompts
    func segmentWithPoints(
        image: NSImage,
        points: [AIPromptPoint]
    ) async throws -> AIMaskResult {
        guard serverStatus == .ready else {
            throw SAM3Error.serverNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        // Convert image to base64 JPEG
        guard let imageData = imageToBase64(image) else {
            throw SAM3Error.imageEncodingFailed
        }

        // Prepare request
        let url = baseURL.appendingPathComponent("segment/points")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "image": imageData,
            "points": points.map { [Double($0.position.x), Double($0.position.y)] },
            "labels": points.map { $0.label }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Make request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SAM3Error.invalidResponse
        }

        let segmentResponse = try JSONDecoder().decode(SAM3SegmentResponse.self, from: data)

        if httpResponse.statusCode != 200 || segmentResponse.status != "ok" {
            throw SAM3Error.serverError(segmentResponse.message ?? "Segmentation failed")
        }

        guard let maskBase64 = segmentResponse.mask,
              let maskData = Data(base64Encoded: maskBase64),
              let bbox = segmentResponse.boundingBox else {
            throw SAM3Error.invalidResponse
        }

        return AIMaskResult(
            maskData: maskData,
            boundingBox: bbox.cgRect,
            confidence: segmentResponse.confidence ?? 0,
            objectId: segmentResponse.objectId ?? UUID().uuidString
        )
    }

    /// Segment image with bounding box prompt
    func segmentWithBox(
        image: NSImage,
        box: CGRect
    ) async throws -> AIMaskResult {
        guard serverStatus == .ready else {
            throw SAM3Error.serverNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        guard let imageData = imageToBase64(image) else {
            throw SAM3Error.imageEncodingFailed
        }

        let url = baseURL.appendingPathComponent("segment/box")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "image": imageData,
            "box": [
                "x": box.origin.x,
                "y": box.origin.y,
                "width": box.width,
                "height": box.height
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SAM3Error.invalidResponse
        }

        let segmentResponse = try JSONDecoder().decode(SAM3SegmentResponse.self, from: data)

        if httpResponse.statusCode != 200 || segmentResponse.status != "ok" {
            throw SAM3Error.serverError(segmentResponse.message ?? "Segmentation failed")
        }

        guard let maskBase64 = segmentResponse.mask,
              let maskData = Data(base64Encoded: maskBase64),
              let bbox = segmentResponse.boundingBox else {
            throw SAM3Error.invalidResponse
        }

        return AIMaskResult(
            maskData: maskData,
            boundingBox: bbox.cgRect,
            confidence: segmentResponse.confidence ?? 0,
            objectId: segmentResponse.objectId ?? UUID().uuidString
        )
    }

    /// Segment image with text prompt
    func segmentWithText(
        image: NSImage,
        prompt: String
    ) async throws -> AIMaskResult {
        guard serverStatus == .ready else {
            throw SAM3Error.serverNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        guard let imageData = imageToBase64(image) else {
            throw SAM3Error.imageEncodingFailed
        }

        let url = baseURL.appendingPathComponent("segment/text")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "image": imageData,
            "prompt": prompt
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SAM3Error.invalidResponse
        }

        let segmentResponse = try JSONDecoder().decode(SAM3SegmentResponse.self, from: data)

        if httpResponse.statusCode == 501 {
            // Text prompts not supported
            throw SAM3Error.textPromptsNotSupported(segmentResponse.hint ?? "Use point prompts instead")
        }

        if httpResponse.statusCode != 200 || segmentResponse.status != "ok" {
            throw SAM3Error.serverError(segmentResponse.message ?? "Segmentation failed")
        }

        guard let maskBase64 = segmentResponse.mask,
              let maskData = Data(base64Encoded: maskBase64),
              let bbox = segmentResponse.boundingBox else {
            throw SAM3Error.invalidResponse
        }

        return AIMaskResult(
            maskData: maskData,
            boundingBox: bbox.cgRect,
            confidence: segmentResponse.confidence ?? 0,
            objectId: segmentResponse.objectId ?? UUID().uuidString
        )
    }

    // MARK: - Helpers

    private func findPythonExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
            "/usr/bin/python3"
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                // Verify it's Python 3.10+
                if verifyPythonVersion(path: path) {
                    return path
                }
            }
        }

        // Try which python3
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty, verifyPythonVersion(path: path) {
                return path
            }
        } catch {
            // Ignore
        }

        return nil
    }

    private func verifyPythonVersion(path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let versionStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let parts = versionStr.components(separatedBy: ".")
                if let major = Int(parts[0]), let minor = Int(parts[1]) {
                    return major >= 3 && minor >= 10
                }
            }
        } catch {
            // Ignore
        }

        return false
    }

    private func findServerScript() -> String? {
        // Check in bundle resources (both root and python/ subdirectory)
        if let bundlePath = Bundle.main.resourcePath {
            // Check root of Resources (how Xcode typically copies)
            let rootPath = (bundlePath as NSString).appendingPathComponent("sam3_server.py")
            if FileManager.default.fileExists(atPath: rootPath) {
                return rootPath
            }

            // Check python/ subdirectory
            let subPath = (bundlePath as NSString).appendingPathComponent("python/sam3_server.py")
            if FileManager.default.fileExists(atPath: subPath) {
                return subPath
            }
        }

        // Check in development location (Xcode build)
        if let range = Bundle.main.bundlePath.range(of: "/Build/") {
            let projectPath = String(Bundle.main.bundlePath[..<range.lowerBound])
            let devPath = projectPath + "/cropaway/Resources/python/sam3_server.py"
            if FileManager.default.fileExists(atPath: devPath) {
                return devPath
            }
        }

        // Check relative to source (for development)
        let sourceLocations = [
            FileManager.default.currentDirectoryPath + "/cropaway/Resources/python/sam3_server.py",
            NSHomeDirectory() + "/Documents/GitHub/cropaway/cropaway/cropaway/Resources/python/sam3_server.py"
        ]

        for path in sourceLocations {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func imageToBase64(_ image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            return nil
        }

        return jpegData.base64EncodedString()
    }
}

// MARK: - Errors

enum SAM3Error: LocalizedError {
    case pythonNotFound
    case scriptNotFound
    case serverStartFailed
    case serverNotReady
    case invalidResponse
    case imageEncodingFailed
    case serverError(String)
    case textPromptsNotSupported(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python 3.10+ not found. Please install Python."
        case .scriptNotFound:
            return "SAM3 server script not found."
        case .serverStartFailed:
            return "Failed to start SAM3 server."
        case .serverNotReady:
            return "SAM3 server not ready. Please initialize first."
        case .invalidResponse:
            return "Invalid response from SAM3 server."
        case .imageEncodingFailed:
            return "Failed to encode image."
        case .serverError(let message):
            return "SAM3 server error: \(message)"
        case .textPromptsNotSupported(let hint):
            return "Text prompts not supported. \(hint)"
        }
    }
}

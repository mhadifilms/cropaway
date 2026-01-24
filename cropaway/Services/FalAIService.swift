//
//  FalAIService.swift
//  cropaway
//
//  Service for communicating with fal.ai SAM3 video tracking API.
//  API Reference: https://fal.ai/models/fal-ai/sam-3/video-rle
//

import Foundation
import AppKit
import AVFoundation
import Combine

/// Status of fal.ai processing
enum FalAIStatus: Equatable {
    case idle
    case uploading(progress: Double)
    case processing(progress: Double)
    case downloading
    case extracting
    case completed
    case error(String)
}

/// Result from fal.ai video tracking
struct TrackingResult {
    let masks: [Int: Data]            // frame_index -> RLE mask data (pixel-perfect segmentation)
    let boundingBoxes: [Int: CGRect]  // frame_index -> bounding box (normalized 0-1, derived from masks)
    let frameCount: Int
}

/// Errors from fal.ai service
enum FalAIError: LocalizedError {
    case noAPIKey
    case uploadFailed(String)
    case jobSubmissionFailed(String)
    case processingFailed(String)
    case downloadFailed(String)
    case extractionFailed(String)
    case invalidResponse
    case noBoundingBoxData
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your fal.ai API key in settings."
        case .uploadFailed(let message):
            return "Failed to upload video: \(message)"
        case .jobSubmissionFailed(let message):
            return "Failed to submit tracking job: \(message)"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .downloadFailed(let message):
            return "Failed to download results: \(message)"
        case .extractionFailed(let message):
            return "Failed to extract bounding box data: \(message)"
        case .invalidResponse:
            return "Invalid response from fal.ai API"
        case .noBoundingBoxData:
            return "No bounding box data returned. The object may not have been detected."
        case .timeout:
            return "Request timed out after 30 minutes"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}

/// Service for fal.ai SAM3 video tracking API
@MainActor
final class FalAIService: ObservableObject {
    static let shared = FalAIService()

    @Published var status: FalAIStatus = .idle
    @Published var isProcessing = false
    @Published var lastError: String?

    private let session: URLSession
    private var currentTask: Task<TrackingResult, Error>?

    // API endpoints - using video-rle which returns bounding box coordinates directly
    private let queueEndpoint = "https://queue.fal.run/fal-ai/sam-3/video-rle"
    private let storageEndpoint = "https://fal.ai/api/storage/upload/initiate"
    private let statusBaseURL = "https://queue.fal.run/fal-ai/sam-3/video-rle/requests"

    // UserDefaults key for API key
    private let apiKeyKey = "FalAIAPIKey"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300  // 5 minute timeout for uploads
        config.timeoutIntervalForResource = 1800  // 30 minute timeout for processing
        self.session = URLSession(configuration: config)
    }

    // MARK: - API Key Management

    var hasAPIKey: Bool {
        guard let key = UserDefaults.standard.string(forKey: apiKeyKey) else {
            return false
        }
        return !key.isEmpty
    }

    var apiKey: String? {
        UserDefaults.standard.string(forKey: apiKeyKey)
    }

    func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: apiKeyKey)
    }

    func removeAPIKey() {
        UserDefaults.standard.removeObject(forKey: apiKeyKey)
    }

    func isValidAPIKeyFormat(_ key: String) -> Bool {
        return !key.isEmpty && key.count >= 20
    }

    // MARK: - Video Tracking

    /// Track an object in a video using text or point prompt
    /// - Parameters:
    ///   - videoURL: Local URL of the video file
    ///   - prompt: Text description of object to track (e.g., "person", "car")
    ///   - pointPrompt: Click point in normalized 0-1 coordinates for frame 0
    ///   - frameRate: Video frame rate for timestamp calculation
    func trackObject(
        videoURL: URL,
        prompt: String? = nil,
        pointPrompt: CGPoint? = nil,
        frameRate: Double = 30.0
    ) async throws -> TrackingResult {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw FalAIError.noAPIKey
        }

        isProcessing = true
        status = .uploading(progress: 0)
        lastError = nil

        do {
            // Get source video dimensions for coordinate conversion
            let sourceDimensions = await getVideoDimensions(videoURL) ?? CGSize(width: 1920, height: 1080)
            print("[FalAI] Source video dimensions: \(sourceDimensions)")

            // Step 1: Upload video to fal.ai storage
            let uploadedURL = try await uploadVideo(videoURL, apiKey: apiKey)

            // Step 2: Submit tracking job
            status = .processing(progress: 0)
            let submission = try await submitJob(
                videoURL: uploadedURL,
                prompt: prompt,
                pointPrompt: pointPrompt,
                sourceDimensions: sourceDimensions,
                apiKey: apiKey
            )

            // Step 3: Poll for results using the returned URLs
            let result = try await pollForResult(submission: submission, apiKey: apiKey, frameRate: frameRate, videoDimensions: sourceDimensions)

            status = .completed
            isProcessing = false
            return result

        } catch {
            isProcessing = false
            let errorMessage = error.localizedDescription
            status = .error(errorMessage)
            lastError = errorMessage
            throw error
        }
    }

    /// Cancel current tracking operation
    func cancelTracking() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        status = .idle
    }

    // MARK: - Private Methods

    /// Get video dimensions using AVFoundation
    private func getVideoDimensions(_ url: URL) async -> CGSize? {
        let asset = AVAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        let size = try? await track.load(.naturalSize)
        let transform = try? await track.load(.preferredTransform)
        guard let size = size else { return nil }

        // Apply transform to handle rotated videos
        if let transform = transform {
            let isRotated = transform.a == 0 && transform.d == 0
            if isRotated {
                return CGSize(width: abs(size.height), height: abs(size.width))
            }
        }
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    /// Create a lightweight H.264 proxy for upload (same resolution, compressed)
    private func createProxy(_ sourceURL: URL) async throws -> URL {
        print("[FalAI] Creating proxy for: \(sourceURL.lastPathComponent)")

        let tempDir = FileManager.default.temporaryDirectory
        let proxyURL = tempDir.appendingPathComponent("proxy_\(UUID().uuidString).mp4")

        // Find ffmpeg
        let ffmpegPath = findFFmpegPath()
        guard let ffmpeg = ffmpegPath else {
            throw FalAIError.uploadFailed("FFmpeg not found. Please install FFmpeg via Homebrew.")
        }

        // Build ffmpeg command for proxy: same resolution, H.264 compressed
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-i", sourceURL.path,
            "-c:v", "libx264",               // H.264 codec
            "-preset", "veryfast",           // Fast encoding
            "-crf", "28",                    // Reasonable quality (smaller file)
            "-c:a", "aac",                   // AAC audio
            "-b:a", "128k",                  // 128kbps audio
            "-movflags", "+faststart",       // Web-optimized
            "-y",                            // Overwrite
            proxyURL.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw FalAIError.uploadFailed("Proxy creation failed: \(errorStr)")
        }

        // Verify proxy was created
        guard FileManager.default.fileExists(atPath: proxyURL.path) else {
            throw FalAIError.uploadFailed("Proxy file was not created")
        }

        let proxySize = try FileManager.default.attributesOfItem(atPath: proxyURL.path)[.size] as? Int64 ?? 0
        print("[FalAI] Proxy created: \(ByteCountFormatter.string(fromByteCount: proxySize, countStyle: .file))")

        return proxyURL
    }

    /// Find FFmpeg executable path
    private func findFFmpegPath() -> String? {
        // Check common locations
        let paths = [
            "/opt/homebrew/bin/ffmpeg",      // Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",         // Intel Homebrew
            "/usr/bin/ffmpeg"                // System
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try which command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path = path, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return path
        }

        return nil
    }

    /// Upload video to fal.ai CDN storage
    /// Flow: 1) Create proxy, 2) Get upload token, 3) Upload proxy to CDN, 4) Return access URL
    private func uploadVideo(_ localURL: URL, apiKey: String) async throws -> URL {
        print("[FalAI] Preparing video: \(localURL.lastPathComponent)")

        // Check file size - if over 50MB, create a proxy
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
        print("[FalAI] Original size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")

        let uploadURL: URL
        var proxyToCleanup: URL? = nil

        if fileSize > 50 * 1024 * 1024 {  // Over 50MB - create proxy
            status = .uploading(progress: 0.1)
            let proxyURL = try await createProxy(localURL)
            proxyToCleanup = proxyURL
            uploadURL = proxyURL
        } else {
            uploadURL = localURL
        }

        defer {
            // Clean up proxy file if created
            if let proxy = proxyToCleanup {
                try? FileManager.default.removeItem(at: proxy)
            }
        }

        // Read video data
        let videoData: Data
        do {
            videoData = try Data(contentsOf: uploadURL)
        } catch {
            throw FalAIError.uploadFailed("Could not read video file: \(error.localizedDescription)")
        }

        print("[FalAI] Upload size: \(ByteCountFormatter.string(fromByteCount: Int64(videoData.count), countStyle: .file))")

        // Step 1: Get upload token (POST with empty JSON body)
        status = .uploading(progress: 0.2)
        print("[FalAI] Getting upload token...")
        let tokenURL = URL(string: "https://rest.alpha.fal.ai/storage/auth/token?storage_type=fal-cdn-v3")!
        var tokenRequest = URLRequest(url: tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        tokenRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        tokenRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        tokenRequest.httpBody = "{}".data(using: .utf8)

        let (tokenData, tokenResponse) = try await session.data(for: tokenRequest)

        guard let tokenHttpResponse = tokenResponse as? HTTPURLResponse else {
            throw FalAIError.uploadFailed("Invalid token response")
        }

        if tokenHttpResponse.statusCode != 200 {
            let errorBody = String(data: tokenData, encoding: .utf8) ?? "Unknown error"
            throw FalAIError.uploadFailed("Failed to get upload token: HTTP \(tokenHttpResponse.statusCode): \(errorBody)")
        }

        guard let tokenJson = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let token = tokenJson["token"] as? String,
              let tokenType = tokenJson["token_type"] as? String else {
            let responseStr = String(data: tokenData, encoding: .utf8) ?? "empty"
            throw FalAIError.uploadFailed("Could not parse token response: \(responseStr)")
        }

        // Get base upload URL (try multiple keys, default to v3.fal.media)
        let baseUploadURL = (tokenJson["base_url"] as? String)
            ?? (tokenJson["base_upload_url"] as? String)
            ?? "https://v3.fal.media"
        print("[FalAI] Got upload token, base URL: \(baseUploadURL)")

        // Step 2: Upload file to CDN
        status = .uploading(progress: 0.4)
        let cdnUploadURL = URL(string: "\(baseUploadURL)/files/upload")!
        var uploadRequest = URLRequest(url: cdnUploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("\(tokenType) \(token)", forHTTPHeaderField: "Authorization")
        uploadRequest.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue("proxy.mp4", forHTTPHeaderField: "X-Fal-File-Name")
        uploadRequest.httpBody = videoData

        print("[FalAI] Uploading to: \(cdnUploadURL)")

        let (uploadData, uploadResponse) = try await session.data(for: uploadRequest)

        guard let uploadHttpResponse = uploadResponse as? HTTPURLResponse else {
            throw FalAIError.uploadFailed("Invalid upload response")
        }

        if uploadHttpResponse.statusCode != 200 && uploadHttpResponse.statusCode != 201 {
            let errorBody = String(data: uploadData, encoding: .utf8) ?? "Unknown error"
            throw FalAIError.uploadFailed("Upload failed: HTTP \(uploadHttpResponse.statusCode): \(errorBody)")
        }

        // Parse response to get access URL
        guard let uploadJson = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let accessUrlString = uploadJson["access_url"] as? String,
              let accessURL = URL(string: accessUrlString) else {
            // Try alternate response format (might just be "url")
            if let uploadJson = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
               let urlString = uploadJson["url"] as? String,
               let resultURL = URL(string: urlString) {
                print("[FalAI] Video uploaded: \(resultURL)")
                status = .uploading(progress: 1.0)
                return resultURL
            }
            let responseStr = String(data: uploadData, encoding: .utf8) ?? "empty"
            throw FalAIError.uploadFailed("Could not parse upload response: \(responseStr)")
        }

        print("[FalAI] Video uploaded: \(accessURL)")
        status = .uploading(progress: 1.0)
        return accessURL
    }

    /// Queue submission response with URLs
    struct QueueSubmissionResponse {
        let requestId: String
        let statusUrl: URL
        let responseUrl: URL
    }

    /// Submit tracking job to fal.ai queue
    private func submitJob(
        videoURL: URL,
        prompt: String?,
        pointPrompt: CGPoint?,
        sourceDimensions: CGSize,
        apiKey: String
    ) async throws -> QueueSubmissionResponse {
        print("[FalAI] Submitting tracking job")

        var request = URLRequest(url: URL(string: queueEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Build request body per video-rle API spec
        // video-rle returns boxes array directly in JSON response
        var body: [String: Any] = [
            "video_url": videoURL.absoluteString
        ]

        // Add text prompt if provided
        if let prompt = prompt, !prompt.isEmpty {
            body["prompt"] = prompt
        }

        // Add point prompt if provided (for frame 0)
        // Point coordinates coming in are NORMALIZED (0-1)
        // API expects PIXEL coordinates relative to video dimensions
        // Proxy is same resolution as source, so use source dimensions
        if let point = pointPrompt {
            let pixelX = Int(point.x * sourceDimensions.width)
            let pixelY = Int(point.y * sourceDimensions.height)

            let pointPromptObj: [String: Any] = [
                "x": pixelX,
                "y": pixelY,
                "label": 1,  // 1 = foreground
                "frame_index": 0,
                "object_id": 1
            ]
            body["point_prompts"] = [pointPromptObj]
            print("[FalAI] Point prompt: pixel=(\(pixelX), \(pixelY)) normalized=(\(point.x), \(point.y)) videoSize=\(sourceDimensions)")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[FalAI] Request body: \(body)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FalAIError.jobSubmissionFailed("Invalid response")
        }

        let responseStr = String(data: data, encoding: .utf8) ?? "empty"
        print("[FalAI] Submit response: \(responseStr)")

        if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 && httpResponse.statusCode != 202 {
            throw FalAIError.jobSubmissionFailed("HTTP \(httpResponse.statusCode): \(responseStr)")
        }

        // Parse response to get request_id and URLs
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestId = json["request_id"] as? String else {
            throw FalAIError.jobSubmissionFailed("Could not parse response: \(responseStr)")
        }

        // Get the returned URLs (fal.ai provides these)
        let statusUrlString = json["status_url"] as? String ?? "\(statusBaseURL)/\(requestId)/status"
        let responseUrlString = json["response_url"] as? String ?? "\(statusBaseURL)/\(requestId)"

        guard let statusUrl = URL(string: statusUrlString),
              let responseUrl = URL(string: responseUrlString) else {
            throw FalAIError.jobSubmissionFailed("Invalid URLs in response")
        }

        print("[FalAI] Job submitted: \(requestId)")
        print("[FalAI] Status URL: \(statusUrl)")
        print("[FalAI] Response URL: \(responseUrl)")

        return QueueSubmissionResponse(requestId: requestId, statusUrl: statusUrl, responseUrl: responseUrl)
    }

    /// Poll for job completion and get results
    private func pollForResult(submission: QueueSubmissionResponse, apiKey: String, frameRate: Double, videoDimensions: CGSize) async throws -> TrackingResult {
        print("[FalAI] Polling for results: \(submission.requestId)")
        print("[FalAI] Using status URL: \(submission.statusUrl)")

        var statusRequest = URLRequest(url: submission.statusUrl)
        statusRequest.httpMethod = "GET"
        statusRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        statusRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        // Poll until complete (max 30 minutes at 5 second intervals)
        let maxPolls = 360
        var pollCount = 0

        while pollCount < maxPolls {
            try Task.checkCancellation()

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: statusRequest)
            } catch {
                print("[FalAI] Network error during poll: \(error.localizedDescription)")
                // Wait and retry on network errors
                try await Task.sleep(nanoseconds: 5_000_000_000)
                pollCount += 1
                continue
            }

            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                print("[FalAI] Poll HTTP status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    let errorBody = String(data: data, encoding: .utf8) ?? "empty"
                    print("[FalAI] Poll error response: \(errorBody)")
                    // Wait and retry on server errors
                    if httpResponse.statusCode >= 500 {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        pollCount += 1
                        continue
                    }
                }
            }

            let responseStr = String(data: data, encoding: .utf8) ?? "empty"
            print("[FalAI] Poll response: \(responseStr.prefix(500))")

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[FalAI] Failed to parse JSON response")
                try await Task.sleep(nanoseconds: 5_000_000_000)
                pollCount += 1
                continue
            }

            guard let statusString = json["status"] as? String else {
                print("[FalAI] No status field in response, keys: \(json.keys)")
                // Maybe the response IS the result (some APIs return result directly)
                if json["video"] != nil || json["boundingbox_frames_zip"] != nil || json["rle"] != nil {
                    print("[FalAI] Found result data in response, parsing...")
                    return try await parseResult(data, apiKey: apiKey, frameRate: frameRate, videoDimensions: videoDimensions)
                }
                try await Task.sleep(nanoseconds: 5_000_000_000)
                pollCount += 1
                continue
            }

            print("[FalAI] Status: \(statusString)")

            switch statusString {
            case "COMPLETED":
                // Fetch the full result using the response URL from submission
                var resultRequest = URLRequest(url: submission.responseUrl)
                resultRequest.httpMethod = "GET"
                resultRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
                resultRequest.setValue("application/json", forHTTPHeaderField: "Accept")

                print("[FalAI] Fetching result from: \(submission.responseUrl)")
                let (resultData, _) = try await session.data(for: resultRequest)
                return try await parseResult(resultData, apiKey: apiKey, frameRate: frameRate, videoDimensions: videoDimensions)

            case "FAILED":
                let errorMessage = json["error"] as? String ?? "Processing failed"
                throw FalAIError.processingFailed(errorMessage)

            case "IN_PROGRESS", "IN_QUEUE", "PENDING":
                // Update progress if available
                if let logs = json["logs"] as? [[String: Any]], let lastLog = logs.last {
                    if let message = lastLog["message"] as? String {
                        print("[FalAI] Log: \(message)")
                    }
                }

            default:
                print("[FalAI] Unknown status: \(statusString)")
            }

            // Wait before next poll
            try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
            pollCount += 1
        }

        throw FalAIError.timeout
    }

    /// Parse the result from fal.ai video-rle endpoint
    /// Response format: { rle: [...], boxes: [[cx, cy, w, h], ...] }
    private func parseResult(_ data: Data, apiKey: String, frameRate: Double, videoDimensions: CGSize) async throws -> TrackingResult {
        print("[FalAI] Parsing video-rle result")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let responseStr = String(data: data, encoding: .utf8) ?? "empty"
            print("[FalAI] Invalid JSON response: \(responseStr)")
            throw FalAIError.invalidResponse
        }

        print("[FalAI] Response keys: \(json.keys)")

        // Use video dimensions for RLE size if not provided by API
        // COCO RLE format uses [height, width]
        let defaultSize = [Int(videoDimensions.height), Int(videoDimensions.width)]
        print("[FalAI] Video dimensions for RLE: \(videoDimensions) -> size: \(defaultSize)")

        var masks: [Int: Data] = [:]
        var boundingBoxes: [Int: CGRect] = [:]
        var frameCount = 0

        // Extract RLE masks - primary data from video-rle endpoint
        if let rleArray = json["rle"] as? [Any] {
            print("[FalAI] Found rle array with \(rleArray.count) items")
            frameCount = rleArray.count

            for (frameIndex, rle) in rleArray.enumerated() {
                if let rleData = convertRLEToData(rle, defaultSize: defaultSize) {
                    masks[frameIndex] = rleData
                }
            }
        }

        // Extract bounding boxes (derived from masks by API)
        if let boxes = json["boxes"] as? [[Double]] {
            print("[FalAI] Found boxes array with \(boxes.count) items")
            frameCount = max(frameCount, boxes.count)

            for (frameIndex, box) in boxes.enumerated() {
                if box.count >= 4 {
                    // Convert from center-based [cx, cy, w, h] to origin-based CGRect
                    let cx = box[0]
                    let cy = box[1]
                    let w = box[2]
                    let h = box[3]

                    boundingBoxes[frameIndex] = CGRect(
                        x: cx - w / 2,
                        y: cy - h / 2,
                        width: w,
                        height: h
                    )
                }
            }
        }

        // Check metadata array for per-frame data
        if let metadata = json["metadata"] as? [[String: Any]] {
            print("[FalAI] Found metadata array with \(metadata.count) items")

            for (idx, item) in metadata.enumerated() {
                let index = item["index"] as? Int ?? idx

                // Extract RLE from metadata
                if masks[index] == nil {
                    if let rle = item["rle"], let rleData = convertRLEToData(rle, defaultSize: defaultSize) {
                        masks[index] = rleData
                    }
                }

                // Extract bounding box from metadata
                if boundingBoxes[index] == nil, let box = item["box"] as? [Double], box.count >= 4 {
                    let cx = box[0]
                    let cy = box[1]
                    let w = box[2]
                    let h = box[3]

                    boundingBoxes[index] = CGRect(
                        x: cx - w / 2,
                        y: cy - h / 2,
                        width: w,
                        height: h
                    )
                }

                frameCount = max(frameCount, index + 1)
            }
        }

        print("[FalAI] Parsed \(masks.count) RLE masks and \(boundingBoxes.count) bounding boxes from \(frameCount) frames")

        if masks.isEmpty {
            throw FalAIError.noBoundingBoxData
        }

        return TrackingResult(
            masks: masks,
            boundingBoxes: boundingBoxes,
            frameCount: frameCount
        )
    }

    /// Convert various RLE formats to Data for storage
    /// - Parameters:
    ///   - rle: RLE data in various formats (string, dict, or array)
    ///   - defaultSize: Video dimensions as [height, width] to use if RLE doesn't include size
    private func convertRLEToData(_ rle: Any, defaultSize: [Int]) -> Data? {
        // If it's already a string (JSON string or raw counts)
        if let rleString = rle as? String {
            print("[FalAI] RLE is string, length=\(rleString.count), prefix=\(rleString.prefix(50))")
            if rleString.hasPrefix("{") {
                // Parse JSON, add size if missing, re-serialize
                if var jsonDict = try? JSONSerialization.jsonObject(with: rleString.data(using: .utf8)!) as? [String: Any] {
                    let hadSize = jsonDict["size"] != nil
                    if !hadSize {
                        jsonDict["size"] = defaultSize
                    }
                    print("[FalAI] JSON dict keys: \(jsonDict.keys), hadSize=\(hadSize)")
                    return try? JSONSerialization.data(withJSONObject: jsonDict)
                }
                return rleString.data(using: .utf8)
            }
            // Raw counts string - wrap with size
            print("[FalAI] Raw counts string, wrapping with size=\(defaultSize)")
            let dict: [String: Any] = ["counts": rleString, "size": defaultSize]
            return try? JSONSerialization.data(withJSONObject: dict)
        }

        // If it's a dictionary (standard COCO RLE format)
        if var rleDict = rle as? [String: Any] {
            let hadSize = rleDict["size"] != nil
            if !hadSize {
                rleDict["size"] = defaultSize
            }
            print("[FalAI] RLE dict keys: \(rleDict.keys), hadSize=\(hadSize)")
            return try? JSONSerialization.data(withJSONObject: rleDict)
        }

        // If it's an array of counts
        if let counts = rle as? [Int] {
            print("[FalAI] RLE is array of \(counts.count) counts, adding size=\(defaultSize)")
            let rleDict: [String: Any] = ["counts": counts, "size": defaultSize]
            return try? JSONSerialization.data(withJSONObject: rleDict)
        }

        print("[FalAI] Unknown RLE type: \(type(of: rle))")
        return nil
    }
}

//
//  FFmpegExportService.swift
//  cropaway
//

import Foundation
import AppKit
import CoreGraphics
import CoreImage

final class FFmpegExportService {
    private var process: Process?
    private var isCancelled = false
    private var tempMaskURLs: [URL] = []  // Track temp files for cleanup
    private let maskRenderer = CropMaskRenderer()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func cancel() {
        isCancelled = true
        process?.terminate()
        cleanupTempFiles()
    }

    /// Clean up temporary mask files created during export
    private func cleanupTempFiles() {
        for url in tempMaskURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempMaskURLs.removeAll()
    }

    func exportVideo(
        source: VideoItem,
        cropConfig: CropConfiguration,
        exportConfig: ExportConfiguration,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        isCancelled = false

        guard let outputURL = exportConfig.outputURL else {
            throw ExportError.noOutputURL
        }

        guard let ffmpegPath = findFFmpeg() else {
            throw ExportError.ffmpegNotFound
        }

        // Delete existing file
        try? FileManager.default.removeItem(at: outputURL)

        let metadata = source.metadata
        let sourceURL = source.sourceURL
        // Use per-video settings from cropConfig
        let preserveDimensions = cropConfig.preserveWidth
        let enableAlpha = cropConfig.enableAlphaChannel

        // Build FFmpeg arguments
        var args: [String] = ["-y", "-i", sourceURL.path]

        // Calculate crop parameters
        let cropX = Int(cropConfig.cropRect.origin.x * Double(metadata.width))
        let cropY = Int(cropConfig.cropRect.origin.y * Double(metadata.height))
        var cropW = Int(cropConfig.cropRect.width * Double(metadata.width))
        var cropH = Int(cropConfig.cropRect.height * Double(metadata.height))
        // Ensure even dimensions
        cropW = cropW % 2 == 0 ? cropW : cropW - 1
        cropH = cropH % 2 == 0 ? cropH : cropH - 1

        // Determine if actual cropping is needed
        let needsCrop = cropW != metadata.width || cropH != metadata.height || cropX != 0 || cropY != 0

        // Add crop/mask filter based on mode
        switch cropConfig.mode {
        case .rectangle:
            if needsCrop {
                if preserveDimensions {
                    // Crop then pad back to original dimensions with black/alpha
                    // First crop, then pad back to original size positioning the crop at correct offset
                    if enableAlpha {
                        // With alpha: use geq to create transparent background
                        args += ["-vf", "crop=\(cropW):\(cropH):\(cropX):\(cropY),pad=\(metadata.width):\(metadata.height):\(cropX):\(cropY):color=black@0"]
                    } else {
                        // Black background
                        args += ["-vf", "crop=\(cropW):\(cropH):\(cropX):\(cropY),pad=\(metadata.width):\(metadata.height):\(cropX):\(cropY):black"]
                    }
                } else {
                    // Crop only — output is the cropped region at its natural size (no stretch)
                    args += ["-vf", "crop=\(cropW):\(cropH):\(cropX):\(cropY)"]
                }
            }

        case .circle, .freehand, .ai:
            // Generate mask and use it
            let maskURL = try await generateMaskImage(cropConfig: cropConfig, size: CGSize(width: metadata.width, height: metadata.height))
            args = ["-y", "-i", sourceURL.path, "-i", maskURL.path]

            if preserveDimensions {
                // Keep original dimensions with masked area
                if enableAlpha {
                    // Output with alpha - use mask as alpha channel
                    args += ["-filter_complex", "[1:v]format=gray[mask];[0:v][mask]alphamerge"]
                } else {
                    // Output with black background - multiply
                    args += ["-filter_complex", "[0:v][1:v]blend=all_mode=multiply"]
                }
            } else {
                // Crop to bounding box of the mask — output at natural size (no stretch)
                let boundingBox = getMaskBoundingBox(cropConfig: cropConfig, size: CGSize(width: metadata.width, height: metadata.height))
                let bboxX = Int(boundingBox.origin.x)
                let bboxY = Int(boundingBox.origin.y)
                var bboxW = Int(boundingBox.width)
                var bboxH = Int(boundingBox.height)
                // Ensure even dimensions
                bboxW = bboxW % 2 == 0 ? bboxW : bboxW - 1
                bboxH = bboxH % 2 == 0 ? bboxH : bboxH - 1

                if enableAlpha {
                    args += ["-filter_complex", "[1:v]format=gray[mask];[0:v][mask]alphamerge,crop=\(bboxW):\(bboxH):\(bboxX):\(bboxY)"]
                } else {
                    args += ["-filter_complex", "[0:v][1:v]blend=all_mode=multiply,crop=\(bboxW):\(bboxH):\(bboxX):\(bboxY)"]
                }
            }
        }

        // Codec selection - can only use copy if no filtering needed
        let needsReencode = cropConfig.mode != .rectangle || enableAlpha || needsCrop

        if !needsReencode {
            // No changes needed - stream copy
            args += ["-c:v", "copy"]
        } else {
            // Custom crops need re-encode - use VideoToolbox hardware acceleration
            // Preserve source bitrate for H.264/HEVC (ProRes uses profile, not bitrate)
            let sourceBitrate = metadata.bitRate > 0 ? metadata.bitRate : 10_000_000  // 10 Mbps default
            let targetBitrate = "\(Int(Double(sourceBitrate) / 1000))k"  // match source in kbps

            let codec = metadata.codecType.lowercased()
            if codec.contains("h.264") || codec.contains("avc") {
                args += ["-c:v", "h264_videotoolbox", "-b:v", targetBitrate]
            } else if codec.contains("hevc") || codec.contains("h.265") || codec.hasPrefix("hvc") || codec.hasPrefix("hev") {
                args += ["-c:v", "hevc_videotoolbox", "-b:v", targetBitrate]
            } else if codec.contains("prores") || codec.hasPrefix("ap") {
                // Use VideoToolbox ProRes hardware encoder - match source profile by fourCC
                args += ["-c:v", "prores_videotoolbox"]
                if codec == "ap4x" {
                    args += ["-profile:v", "xq"]
                } else if codec == "ap4h" || codec == "ap4c" || enableAlpha {
                    args += ["-profile:v", "4444"]
                } else if codec == "apch" {
                    args += ["-profile:v", "hq"]
                } else if codec == "apcn" {
                    args += ["-profile:v", "standard"]
                } else if codec == "apcs" {
                    args += ["-profile:v", "lt"]
                } else if codec == "apco" {
                    args += ["-profile:v", "proxy"]
                } else {
                    args += ["-profile:v", "auto"]
                }
            } else {
                // Fallback: use VideoToolbox ProRes HQ
                args += ["-c:v", "prores_videotoolbox", "-profile:v", "hq"]
            }

            // Pixel format: preserve bit depth (8/10/12/16) and chroma. ProRes 4444/XQ support 12-bit; 422 is 10-bit. HEVC 10-bit max; H.264 8-bit.
            let isProRes4444 = codec == "ap4x" || codec == "ap4h" || codec == "ap4c"
            let bitDepth = metadata.bitDepth
            if enableAlpha {
                // Alpha requires 4:4:4. ProRes 4444 supports 12-bit; else 10-bit.
                if isProRes4444 && bitDepth >= 12 {
                    args += ["-pix_fmt", "yuva444p12le"]
                } else {
                    args += ["-pix_fmt", "yuva444p10le"]
                }
            } else if codec.contains("h.264") || codec.contains("avc") {
                // H.264 is 8-bit only; do not set pix_fmt (encoder default)
            } else if codec.contains("hevc") || codec.contains("h.265") || codec.hasPrefix("hvc") || codec.hasPrefix("hev") {
                if bitDepth > 8 {
                    args += ["-pix_fmt", "yuv422p10le"]  // 10-bit max for HEVC; 12/16→10
                }
            } else if isProRes4444 {
                if bitDepth >= 12 {
                    args += ["-pix_fmt", "yuv444p12le"]
                } else if bitDepth > 8 {
                    args += ["-pix_fmt", "yuv444p10le"]
                }
            } else if codec.contains("prores") || codec.hasPrefix("ap") {
                // ProRes 422 (apch, apcn, apcs, apco): 10-bit max
                if bitDepth > 8 {
                    args += ["-pix_fmt", "yuv422p10le"]
                }
            }

            // Preserve color metadata (HDR and SDR): primaries, transfer, YCbCr matrix
            if metadata.isHDR {
                if let primaries = metadata.colorPrimaries {
                    if primaries.contains("2020") { args += ["-color_primaries", "bt2020"] }
                    else if primaries.contains("P3") { args += ["-color_primaries", "smpte432"] }
                    else if primaries.contains("709") { args += ["-color_primaries", "bt709"] }
                    else if primaries.contains("601") { args += ["-color_primaries", "bt601-625"] }
                }
                if let transfer = metadata.transferFunction {
                    if transfer.contains("2084") || transfer.contains("PQ") { args += ["-color_trc", "smpte2084"] }
                    else if transfer.contains("HLG") { args += ["-color_trc", "arib-std-b67"] }
                    else if transfer.contains("709") { args += ["-color_trc", "bt709"] }
                }
            } else if let primaries = metadata.colorPrimaries {
                if primaries.contains("709") { args += ["-color_primaries", "bt709"] }
                else if primaries.contains("601") { args += ["-color_primaries", "bt601-625"] }
                else if primaries.contains("2020") { args += ["-color_primaries", "bt2020"] }
                else if primaries.contains("P3") { args += ["-color_primaries", "smpte432"] }
            }
            if !metadata.isHDR, let transfer = metadata.transferFunction {
                if transfer.contains("709") { args += ["-color_trc", "bt709"] }
                else if transfer.contains("2084") || transfer.contains("PQ") { args += ["-color_trc", "smpte2084"] }
                else if transfer.contains("HLG") { args += ["-color_trc", "arib-std-b67"] }
            }
            // YCbCr matrix (colorspace) for both HDR and SDR
            if let matrix = metadata.colorMatrix {
                if matrix.contains("2020") { args += ["-colorspace", "bt2020nc"] }
                else if matrix.contains("709") { args += ["-colorspace", "bt709"] }
                else if matrix.contains("601") { args += ["-colorspace", "bt601-6"] }
                else if matrix.contains("240") { args += ["-colorspace", "smpte240m"] }
            } else if metadata.isHDR, (metadata.colorPrimaries?.contains("2020") ?? false) {
                args += ["-colorspace", "bt2020nc"]
            }
        }

        // Copy audio
        args += ["-c:a", "copy"]

        // Copy global/container metadata from source (creation time, etc.)
        args += ["-map_metadata", "0"]

        // Output
        args += [outputURL.path]

        print("FFmpeg: \(ffmpegPath) \(args.joined(separator: " "))")

        // Run FFmpeg
        defer { cleanupTempFiles() }  // Always clean up temp files
        try await runFFmpeg(path: ffmpegPath, arguments: args, duration: metadata.duration, progressHandler: progressHandler)

        return outputURL
    }

    private func findFFmpeg() -> String? {
        // First check if FFmpeg is bundled with the app
        if let bundledPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }

        // Fall back to system installations (useful during development)
        let systemPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func getMaskBoundingBox(cropConfig: CropConfiguration, size: CGSize) -> CGRect {
        let base = Self.getCropPixelRect(cropConfig: cropConfig, size: size)
        let params = cropConfig.maskRefinement
        let morphExpansion = Double(params.radius * max(1, params.iterations))
        let featherExpansion = params.smoothing + params.blurRadius + params.postFilter
        let inOutExpansion = max(0, params.inOutRatio) * max(2.0, params.blurRadius + 4.0)
        let totalExpansion = CGFloat(morphExpansion + featherExpansion + inOutExpansion)

        let expanded = base.insetBy(dx: -totalExpansion, dy: -totalExpansion)
        let clamped = expanded.intersection(CGRect(origin: .zero, size: size))
        return clamped.isNull ? base : clamped
    }

    /// Returns output (width, height) for export. When preserveDimensions is false, uses the crop’s natural pixel size.
    static func getOutputDimensions(cropConfig: CropConfiguration, sourceWidth: Int, sourceHeight: Int, preserveDimensions: Bool) -> (width: Int, height: Int) {
        if preserveDimensions {
            return (sourceWidth, sourceHeight)
        }
        let size = CGSize(width: sourceWidth, height: sourceHeight)
        let rect = getCropPixelRect(cropConfig: cropConfig, size: size)
        var w = Int(rect.width)
        var h = Int(rect.height)
        w = w % 2 == 0 ? w : max(2, w - 1)
        h = h % 2 == 0 ? h : max(2, h - 1)
        return (max(2, w), max(2, h))
    }

    private static func getCropPixelRect(cropConfig: CropConfiguration, size: CGSize) -> CGRect {
        switch cropConfig.mode {
        case .rectangle:
            return cropConfig.cropRect.denormalized(to: size)

        case .circle:
            let center = cropConfig.circleCenter.denormalized(to: size)
            let radius = cropConfig.circleRadius * min(size.width, size.height)
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        case .freehand:
            guard !cropConfig.freehandPoints.isEmpty else {
                return CGRect(origin: .zero, size: size)
            }
            let pixelPoints = cropConfig.freehandPoints.map { $0.denormalized(to: size) }
            let xs = pixelPoints.map { $0.x }
            let ys = pixelPoints.map { $0.y }
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? size.width
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? size.height
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        case .ai:
            if cropConfig.aiBoundingBox.width > 0 {
                return cropConfig.aiBoundingBox.denormalized(to: size)
            }
            return CGRect(origin: .zero, size: size)
        }
    }

    private func generateMaskImage(cropConfig: CropConfiguration, size: CGSize) async throws -> URL {
        let maskURL = FileManager.default.temporaryDirectory.appendingPathComponent("mask_\(UUID().uuidString).png")
        tempMaskURLs.append(maskURL)  // Track for cleanup

        let state = InterpolatedCropState(
            cropRect: cropConfig.cropRect,
            edgeInsets: cropConfig.edgeInsets,
            circleCenter: cropConfig.circleCenter,
            circleRadius: cropConfig.circleRadius,
            freehandPoints: cropConfig.freehandPoints,
            freehandPathData: cropConfig.freehandPathData,
            aiMaskData: cropConfig.aiMaskData,
            aiBoundingBox: cropConfig.aiBoundingBox,
            maskRefinement: cropConfig.maskRefinement
        )

        let maskImage = maskRenderer.generateMask(
            mode: cropConfig.mode,
            state: state,
            size: size,
            refinement: cropConfig.maskRefinement,
            guideImage: nil
        )
        let extent = CGRect(origin: .zero, size: size)

        guard let cgImage = ciContext.createCGImage(maskImage, from: extent) else {
            throw ExportError.maskGenerationFailed
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.maskGenerationFailed
        }

        try pngData.write(to: maskURL)
        return maskURL
    }

    private func runFFmpeg(path: String, arguments: [String], duration: Double, progressHandler: @escaping (Double) -> Void) async throws {
        let process = Process()
        self.process = process

        process.executableURL = URL(fileURLWithPath: path)
        // Add -progress pipe:1 for more reliable progress output
        process.arguments = ["-progress", "pipe:1"] + arguments

        // Set environment for Homebrew FFmpeg
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["DYLD_LIBRARY_PATH"] = "/opt/homebrew/lib:/usr/local/lib"
        env["DYLD_FALLBACK_LIBRARY_PATH"] = "/opt/homebrew/lib:/usr/local/lib"
        process.environment = env

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        try process.run()

        let runningProcess = process
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdoutHandle = stdoutPipe.fileHandleForReading

        // Thread-safe stderr collection using actor
        actor StderrCollector {
            var output = ""
            func append(_ text: String) { output += text }
            func get() -> String { output }
        }
        let stderrCollector = StderrCollector()

        // Monitor both stdout (progress) and stderr (errors/fallback progress)
        let monitorTask = Task.detached {
            var lastProgress: Double = 0

            while runningProcess.isRunning {
                // Read stdout for -progress output (more reliable)
                let stdoutData = stdoutHandle.availableData
                if !stdoutData.isEmpty,
                   let output = String(data: stdoutData, encoding: .utf8) {
                    // Parse "out_time_ms=12345678" or "out_time=00:00:01.234"
                    if let range = output.range(of: "out_time_ms=\\d+", options: .regularExpression) {
                        let msString = String(output[range].dropFirst(12))
                        if let ms = Double(msString) {
                            let seconds = ms / 1_000_000.0
                            let progress = min(0.99, seconds / duration)  // Cap at 99% until complete
                            if progress > lastProgress {
                                lastProgress = progress
                                await MainActor.run { progressHandler(progress) }
                            }
                        }
                    } else if let range = output.range(of: "out_time=\\d+:\\d+:\\d+\\.\\d+", options: .regularExpression) {
                        if let time = FFmpegExportService.parseTime(String(output[range].dropFirst(9))) {
                            let progress = min(0.99, time / duration)
                            if progress > lastProgress {
                                lastProgress = progress
                                await MainActor.run { progressHandler(progress) }
                            }
                        }
                    }
                }

                // Also read stderr for errors and fallback progress
                let stderrData = stderrHandle.availableData
                if !stderrData.isEmpty,
                   let output = String(data: stderrData, encoding: .utf8) {
                    await stderrCollector.append(output)
                    // Fallback: Parse "time=00:00:01.23" from stderr
                    if lastProgress == 0,  // Only use if stdout progress not working
                       let range = output.range(of: "time=\\d+:\\d+:\\d+\\.\\d+", options: .regularExpression),
                       let time = FFmpegExportService.parseTime(String(output[range].dropFirst(5))) {
                        let progress = min(0.99, time / duration)
                        if progress > lastProgress {
                            lastProgress = progress
                            await MainActor.run { progressHandler(progress) }
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: 20_000_000)  // Reduced to 20ms for smoother updates
            }
            // Read any remaining output
            if let data = try? stderrHandle.readToEnd(), let output = String(data: data, encoding: .utf8) {
                await stderrCollector.append(output)
            }
        }

        process.waitUntilExit()

        // Wait for monitor task to finish collecting output
        await monitorTask.value

        if isCancelled {
            throw ExportError.cancelled
        }

        if process.terminationStatus != 0 {
            let stderrOutput = await stderrCollector.get()
            print("FFmpeg stderr: \(stderrOutput)")
            throw ExportError.ffmpegFailed(process.terminationStatus)
        }

        // Ensure we report 100% on successful completion
        await MainActor.run { progressHandler(1.0) }
    }

    nonisolated private static func parseTime(_ str: String) -> Double? {
        let parts = str.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    enum ExportError: LocalizedError {
        case noOutputURL, ffmpegNotFound, maskGenerationFailed, ffmpegFailed(Int32), cancelled

        var errorDescription: String? {
            switch self {
            case .noOutputURL:
                return "No output URL specified"
            case .ffmpegNotFound:
                return "FFmpeg is required for video export but was not found. Please reinstall the app or contact support."
            case .maskGenerationFailed:
                return "Failed to generate crop mask"
            case .ffmpegFailed(let code):
                return "Video export failed (FFmpeg error code: \(code))"
            case .cancelled:
                return "Export cancelled"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .ffmpegNotFound:
                return "FFmpeg should be bundled with this app. Try reinstalling or contact support for assistance."
            case .ffmpegFailed:
                return "This may be due to an unsupported video format or corrupt source file. Try a different video."
            default:
                return nil
            }
        }
    }
}

//
//  TimelineExportService.swift
//  cropaway
//

import Foundation
import AVFoundation
import AppKit

/// Service for exporting timeline sequences as a single video
final class TimelineExportService {
    private let ffmpegService = FFmpegExportService()
    private var tempDirectory: URL?

    // MARK: - Public API

    /// Export a timeline sequence to a single video file
    /// - Parameters:
    ///   - timeline: The timeline to export
    ///   - outputURL: Destination URL for the exported video
    ///   - progressHandler: Callback for progress updates (0.0 - 1.0)
    /// - Returns: URL of the exported video
    func exportTimeline(
        _ timeline: Timeline,
        to outputURL: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        guard !timeline.clips.isEmpty else {
            throw TimelineExportError.emptyTimeline
        }

        // Create temp directory for intermediate files
        tempDirectory = try createTempDirectory()
        defer { cleanupTempDirectory() }

        var exportedClipURLs: [URL] = []
        let totalClips = timeline.clips.count
        let clipProgressWeight = 0.8 / Double(totalClips)  // 80% for clip exports
        let _ = 0.2  // 20% for concatenation (reserved for future use)

        // Export each clip with its crop settings
        for (index, clip) in timeline.clips.enumerated() {
            let clipStartProgress = Double(index) * clipProgressWeight

            guard let videoItem = clip.videoItem else {
                throw TimelineExportError.missingVideoItem(clipIndex: index)
            }

            // Create trimmed version of the clip
            let clipURL = try await exportClip(
                clip,
                from: videoItem,
                index: index,
                progressHandler: { clipProgress in
                    let overallProgress = clipStartProgress + clipProgress * clipProgressWeight
                    progressHandler(overallProgress)
                }
            )

            exportedClipURLs.append(clipURL)

            // Generate transition frames if needed (macOS 26+ only)
            if index < timeline.clips.count - 1 {
                if let transition = timeline.transition(afterClipIndex: index),
                   transition.type == .opticalFlow {
                    if #available(macOS 26.0, *) {
                        let nextClip = timeline.clips[index + 1]
                        if let nextVideoItem = nextClip.videoItem {
                            let transitionURL = try await generateTransitionVideo(
                                from: clipURL,
                                to: nextVideoItem,
                                nextClip: nextClip,
                                duration: transition.duration,
                                index: index
                            )
                            exportedClipURLs.append(transitionURL)
                        }
                    }
                    // On older macOS, optical flow transitions are skipped (hard cut)
                }
            }
        }

        // Concatenate all clips
        progressHandler(0.8)
        let finalURL = try await concatenateClips(exportedClipURLs, to: outputURL)

        progressHandler(1.0)
        return finalURL
    }

    // MARK: - Private Methods

    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cropaway_timeline_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func cleanupTempDirectory() {
        guard let tempDir = tempDirectory else { return }
        try? FileManager.default.removeItem(at: tempDir)
        tempDirectory = nil
    }

    /// Export a single clip with its crop settings applied
    private func exportClip(
        _ clip: TimelineClip,
        from videoItem: VideoItem,
        index: Int,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let tempDir = tempDirectory else {
            throw TimelineExportError.noTempDirectory
        }

        let outputURL = tempDir.appendingPathComponent("clip_\(index).mov")

        // Create export configuration from the video item's crop settings
        let config = ExportConfiguration()
        config.preserveWidth = videoItem.cropConfiguration.preserveWidth
        config.enableAlphaChannel = videoItem.cropConfiguration.enableAlphaChannel
        config.outputURL = outputURL

        // Apply trim points
        let startTime = clip.sourceStartTime
        let duration = clip.trimmedDuration

        // Use FFmpeg to export with trim and crop
        try await ffmpegService.exportWithTrim(
            video: videoItem,
            exportConfig: config,
            startTime: startTime,
            duration: duration,
            progressHandler: progressHandler
        )

        return outputURL
    }

    /// Generate optical flow transition video between two clips
    @available(macOS 26.0, *)
    private func generateTransitionVideo(
        from sourceURL: URL,
        to nextVideoItem: VideoItem,
        nextClip: TimelineClip,
        duration: Double,
        index: Int
    ) async throws -> URL {
        guard let tempDir = tempDirectory else {
            throw TimelineExportError.noTempDirectory
        }

        let outputURL = tempDir.appendingPathComponent("transition_\(index).mov")

        // Extract last frame from source clip
        let sourceLastFrame = try await extractLastFrame(from: sourceURL)

        // Extract first frame from next clip (at trim in point)
        let nextFirstFrame = try await extractFirstFrame(
            from: nextVideoItem.sourceURL,
            atTime: nextClip.sourceStartTime
        )

        // Generate interpolated frames using VTFrameProcessor
        let generator = OpticalFlowTransitionGenerator()
        let frameRate: Double = 30.0
        let frameCount = Int(duration * frameRate)

        let interpolatedFrames = try await generator.generateTransitionFrames(
            fromFrame: sourceLastFrame,
            toFrame: nextFirstFrame,
            frameCount: frameCount,
            size: CGSize(width: CVPixelBufferGetWidth(sourceLastFrame),
                        height: CVPixelBufferGetHeight(sourceLastFrame))
        )

        // Write frames to video file
        try await writeFramesToVideo(
            frames: interpolatedFrames,
            outputURL: outputURL,
            frameRate: frameRate
        )

        return outputURL
    }

    /// Fallback transition generation for pre-macOS 26 (simple crossfade)
    private func generateCrossfadeTransition(
        from sourceURL: URL,
        to nextVideoItem: VideoItem,
        nextClip: TimelineClip,
        duration: Double,
        index: Int
    ) async throws -> URL {
        // On older macOS, we just use a hard cut
        // The transition configuration should prevent this from being called
        throw TimelineExportError.opticalFlowUnavailable
    }

    /// Extract the last frame from a video file
    private func extractLastFrame(from url: URL) async throws -> CVPixelBuffer {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let time = CMTime(seconds: duration.seconds - 0.01, preferredTimescale: 600)
        return try await extractFrame(from: asset, at: time)
    }

    /// Extract a frame from a video at a specific time
    private func extractFirstFrame(from url: URL, atTime seconds: Double) async throws -> CVPixelBuffer {
        let asset = AVAsset(url: url)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        return try await extractFrame(from: asset, at: time)
    }

    private func extractFrame(from asset: AVAsset, at time: CMTime) async throws -> CVPixelBuffer {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let (cgImage, _) = try await generator.image(at: time)

        // Convert CGImage to CVPixelBuffer
        let width = cgImage.width
        let height = cgImage.height

        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard let buffer = pixelBuffer else {
            throw TimelineExportError.frameExtractionFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    /// Write an array of pixel buffers to a video file
    private func writeFramesToVideo(
        frames: [CVPixelBuffer],
        outputURL: URL,
        frameRate: Double
    ) async throws {
        guard let firstFrame = frames.first else {
            throw TimelineExportError.noFramesToWrite
        }

        let width = CVPixelBufferGetWidth(firstFrame)
        let height = CVPixelBufferGetHeight(firstFrame)

        // Create AVAssetWriter
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: nil
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)

        for (index, frame) in frames.enumerated() {
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(index))

            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            }

            adaptor.append(frame, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? TimelineExportError.writerFailed
        }
    }

    /// Concatenate multiple video files into one using FFmpeg
    private func concatenateClips(_ clips: [URL], to outputURL: URL) async throws -> URL {
        guard let tempDir = tempDirectory else {
            throw TimelineExportError.noTempDirectory
        }

        // Create concat file list
        let listURL = tempDir.appendingPathComponent("concat_list.txt")
        let listContent = clips.map { "file '\($0.path)'" }.joined(separator: "\n")
        try listContent.write(to: listURL, atomically: true, encoding: .utf8)

        // Run FFmpeg concat
        guard let ffmpegPath = FFmpegExportService.findFFmpegPath() else {
            throw TimelineExportError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", listURL.path,
            "-c", "copy",
            outputURL.path
        ]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw TimelineExportError.concatenationFailed
        }

        return outputURL
    }
}

// MARK: - Errors

enum TimelineExportError: LocalizedError {
    case emptyTimeline
    case missingVideoItem(clipIndex: Int)
    case noTempDirectory
    case frameExtractionFailed
    case noFramesToWrite
    case writerFailed
    case concatenationFailed
    case ffmpegNotFound
    case opticalFlowUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyTimeline:
            return "Timeline has no clips to export"
        case .missingVideoItem(let index):
            return "Video not found for clip at index \(index)"
        case .noTempDirectory:
            return "Failed to create temporary directory"
        case .frameExtractionFailed:
            return "Failed to extract frame from video"
        case .noFramesToWrite:
            return "No frames to write to video"
        case .writerFailed:
            return "Failed to write video file"
        case .concatenationFailed:
            return "Failed to concatenate clips"
        case .ffmpegNotFound:
            return "FFmpeg not found"
        case .opticalFlowUnavailable:
            return "Optical flow transitions require macOS 26 or later"
        }
    }
}

// MARK: - FFmpegExportService Extension

extension FFmpegExportService {
    /// Export a video with trim points applied
    func exportWithTrim(
        video: VideoItem,
        exportConfig: ExportConfiguration,
        startTime: Double,
        duration: Double,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        // TODO: Add -ss and -t flags to FFmpeg for trim support
        // For now, delegate to the standard export method
        _ = try await exportVideo(
            source: video,
            cropConfig: video.cropConfiguration,
            exportConfig: exportConfig,
            progressHandler: progressHandler
        )
    }

    /// Find FFmpeg path (exposed for timeline service)
    static func findFFmpegPath() -> String? {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            Bundle.main.path(forResource: "ffmpeg", ofType: nil)
        ].compactMap { $0 }

        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }
}

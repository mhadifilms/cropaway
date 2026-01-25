//
//  VideoProcessingService.swift
//  cropaway
//

import Foundation
import AVFoundation
import CoreImage
import CoreMedia

final class VideoProcessingService {
    private let maskRenderer = CropMaskRenderer()
    private var isCancelled = false

    // Valid AVVideoYCbCrMatrix values
    private static let validYCbCrMatrices: Set<String> = [
        AVVideoYCbCrMatrix_ITU_R_709_2,
        AVVideoYCbCrMatrix_ITU_R_601_4,
        AVVideoYCbCrMatrix_ITU_R_2020,
        AVVideoYCbCrMatrix_SMPTE_240M_1995
    ]

    /// Validate and return a valid YCbCr matrix, or nil if invalid
    private func validatedColorMatrix(_ matrix: String?, isHDR: Bool) -> String {
        if let matrix = matrix, Self.validYCbCrMatrices.contains(matrix) {
            return matrix
        }
        // Default based on content type
        return isHDR ? AVVideoYCbCrMatrix_ITU_R_2020 : AVVideoYCbCrMatrix_ITU_R_709_2
    }

    func cancel() {
        isCancelled = true
    }

    func processVideo(
        source: VideoItem,
        cropConfig: CropConfiguration,
        exportConfig: ExportConfiguration,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        isCancelled = false

        guard let outputURL = exportConfig.outputURL else {
            throw ProcessingError.noOutputURL
        }

        // Delete existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Create a fresh asset for export (don't share with player to avoid conflict)
        let asset = AVURLAsset(url: source.sourceURL)
        let metadata = source.metadata

        // Validate metadata
        guard metadata.width > 0 && metadata.height > 0 else {
            print("ERROR: Invalid video dimensions: \(metadata.width)x\(metadata.height)")
            throw ProcessingError.noVideoTrack
        }
        print("Exporting video: \(metadata.width)x\(metadata.height), codec: \(metadata.codecType)")

        // Setup reader
        let reader = try AVAssetReader(asset: asset)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProcessingError.noVideoTrack
        }

        // Determine pixel format based on export settings
        let pixelFormat: OSType
        if cropConfig.enableAlphaChannel || metadata.bitDepth > 8 {
            pixelFormat = kCVPixelFormatType_64RGBALE // 16-bit with alpha for HDR/alpha
        } else {
            pixelFormat = kCVPixelFormatType_32BGRA
        }

        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
        readerOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(readerOutput) else {
            throw ProcessingError.cannotAddReaderOutput
        }
        reader.add(readerOutput)

        // Setup writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // Build video output settings
        let videoSettings = try await buildVideoOutputSettings(
            metadata: metadata,
            cropConfig: cropConfig
        )

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        // Preserve transform
        let transform = try await videoTrack.load(.preferredTransform)
        writerInput.transform = transform

        // Pixel buffer adaptor for efficient writing
        let adaptorAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: metadata.width,
            kCVPixelBufferHeightKey as String: metadata.height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: adaptorAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw ProcessingError.cannotAddWriterInput
        }
        writer.add(writerInput)

        // Add audio track (passthrough)
        var audioReaderOutput: AVAssetReaderTrackOutput?
        var audioWriterInput: AVAssetWriterInput?

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            if reader.canAdd(audioOutput) {
                reader.add(audioOutput)
                audioReaderOutput = audioOutput

                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
                audioInput.expectsMediaDataInRealTime = false
                if writer.canAdd(audioInput) {
                    writer.add(audioInput)
                    audioWriterInput = audioInput
                }
            }
        }

        // Start reading/writing
        guard reader.startReading() else {
            print("Reader failed to start: \(reader.error?.localizedDescription ?? "Unknown")")
            throw ProcessingError.readerFailed(reader.error?.localizedDescription ?? "Unknown error")
        }
        print("Reader started successfully")

        guard writer.startWriting() else {
            print("Writer failed to start: \(writer.error?.localizedDescription ?? "Unknown")")
            throw ProcessingError.writerFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
        print("Writer started successfully")

        writer.startSession(atSourceTime: .zero)

        let duration = try await asset.load(.duration)
        let totalSeconds = duration.seconds

        // Process video frames
        try await processVideoFrames(
            readerOutput: readerOutput,
            adaptor: adaptor,
            cropConfig: cropConfig,
            exportConfig: exportConfig,
            videoSize: CGSize(width: metadata.width, height: metadata.height),
            totalSeconds: totalSeconds,
            progressHandler: progressHandler
        )

        // Process audio
        if let audioOutput = audioReaderOutput, let audioInput = audioWriterInput {
            await processAudioSamples(readerOutput: audioOutput, writerInput: audioInput)
        }

        // Finish writing
        print("Video frames processed, finishing write...")
        writerInput.markAsFinished()
        audioWriterInput?.markAsFinished()

        await writer.finishWriting()

        if writer.status == .failed {
            print("Writer failed: \(writer.error?.localizedDescription ?? "Unknown")")
            throw ProcessingError.writerFailed(writer.error?.localizedDescription ?? "Unknown error")
        }

        print("Export completed successfully to: \(outputURL)")
        return outputURL
    }

    private func buildVideoOutputSettings(
        metadata: VideoMetadata,
        cropConfig: CropConfiguration
    ) async throws -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoWidthKey: metadata.width,
            AVVideoHeightKey: metadata.height
        ]

        // Determine codec - match source exactly when possible
        if cropConfig.enableAlphaChannel {
            settings[AVVideoCodecKey] = AVVideoCodecType.proRes4444
        } else {
            // Try to match source codec
            if let codecType = AVVideoCodecType(fourCC: metadata.codecFourCC) {
                settings[AVVideoCodecKey] = codecType
            } else {
                // Fallback to ProRes 422 HQ only if source codec unknown
                settings[AVVideoCodecKey] = AVVideoCodecType.proRes422HQ
            }
        }
        print("Using codec: \(settings[AVVideoCodecKey] ?? "unknown") (source: \(metadata.codecType))")

        // Add compression properties for H.264/HEVC to match source bitrate
        let codec = settings[AVVideoCodecKey] as? AVVideoCodecType
        if codec == .h264 || codec == .hevc {
            var compressionProperties: [String: Any] = [:]

            // Use source bitrate to avoid bloating file size
            // Note: Do NOT set AVVideoQualityKey as it overrides bitrate and causes huge files
            if metadata.bitRate > 0 {
                compressionProperties[AVVideoAverageBitRateKey] = metadata.bitRate
                // Set max bitrate slightly higher to allow for peaks
                compressionProperties[AVVideoMaxKeyFrameIntervalKey] = 30
            }

            if !compressionProperties.isEmpty {
                settings[AVVideoCompressionPropertiesKey] = compressionProperties
                print("Compression: bitRate=\(metadata.bitRate)")
            }
        }

        // Color properties - preserve for both HDR and SDR
        // Validate YCbCr matrix to avoid AVAssetWriterInput crash
        let validMatrix = validatedColorMatrix(metadata.colorMatrix, isHDR: metadata.isHDR)

        if metadata.isHDR {
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: metadata.colorPrimaries ?? AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: metadata.transferFunction ?? AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                AVVideoYCbCrMatrixKey: validMatrix
            ]
        } else {
            // SDR: preserve color space (typically BT.709 or BT.601)
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: metadata.colorPrimaries ?? AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: metadata.transferFunction ?? AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: validMatrix
            ]
        }

        return settings
    }

    private func processVideoFrames(
        readerOutput: AVAssetReaderTrackOutput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        cropConfig: CropConfiguration,
        exportConfig: ExportConfiguration,
        videoSize: CGSize,
        totalSeconds: Double,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        let writerInput = adaptor.assetWriterInput
        var frameCount = 0

        while !isCancelled {
            if writerInput.isReadyForMoreMediaData {
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                    print("Finished reading \(frameCount) frames")
                    break
                }
                frameCount += 1
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let timestamp = presentationTime.seconds

                if frameCount <= 3 || frameCount % 30 == 0 {
                    let percent = totalSeconds > 0 ? Int((timestamp / totalSeconds) * 100) : 0
                    print("Frame \(frameCount) (\(percent)%)")
                }

                // Wrap frame processing in autorelease pool to prevent memory buildup
                let appendSuccess = autoreleasepool { () -> Bool in
                    // Get pixel buffer
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        return true // Skip frame but don't fail
                    }

                    // Get interpolated crop state
                    let cropState: InterpolatedCropState
                    if cropConfig.hasKeyframes {
                        cropState = KeyframeInterpolator.shared.interpolate(
                            keyframes: cropConfig.keyframes,
                            at: timestamp,
                            mode: cropConfig.mode
                        )
                    } else {
                        cropState = InterpolatedCropState(
                            cropRect: cropConfig.cropRect,
                            edgeInsets: cropConfig.edgeInsets,
                            circleCenter: cropConfig.circleCenter,
                            circleRadius: cropConfig.circleRadius,
                            freehandPoints: cropConfig.freehandPoints,
                            freehandPathData: cropConfig.freehandPathData,
                            aiMaskData: cropConfig.aiMaskData,
                            aiBoundingBox: cropConfig.aiBoundingBox
                        )
                    }

                    // Generate mask
                    let mask = maskRenderer.generateMask(
                        mode: cropConfig.mode,
                        state: cropState,
                        size: videoSize
                    )

                    // Apply mask
                    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
                    let outputImage = maskRenderer.applyMask(
                        to: inputImage,
                        mask: mask,
                        preserveWidth: cropConfig.preserveWidth,
                        enableAlpha: cropConfig.enableAlphaChannel
                    )

                    // Create output pixel buffer
                    guard let outputBuffer = createPixelBuffer(
                        from: adaptor.pixelBufferPool,
                        size: videoSize,
                        enableAlpha: cropConfig.enableAlphaChannel
                    ) else {
                        print("WARNING: Failed to create pixel buffer for frame \(frameCount)")
                        return true // Skip frame but don't fail
                    }

                    // Render with alpha support if enabled
                    maskRenderer.render(outputImage, to: outputBuffer, enableAlpha: cropConfig.enableAlphaChannel)

                    // Append
                    return adaptor.append(outputBuffer, withPresentationTime: presentationTime)
                }

                if !appendSuccess {
                    print("ERROR: Failed to append frame \(frameCount)")
                    throw ProcessingError.appendFailed
                }

                // Report progress
                if totalSeconds > 0 {
                    let progress = timestamp / totalSeconds
                    await MainActor.run {
                        progressHandler(min(1.0, progress))
                    }
                }
            } else {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }

        if isCancelled {
            throw ProcessingError.cancelled
        }
    }

    private func processAudioSamples(
        readerOutput: AVAssetReaderTrackOutput,
        writerInput: AVAssetWriterInput
    ) async {
        var waitCount = 0
        let maxWaits = 1000  // Max 10 seconds of waiting (10ms * 1000)

        while !isCancelled {
            if writerInput.isReadyForMoreMediaData {
                waitCount = 0  // Reset wait counter
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                    break
                }
                if !writerInput.append(sampleBuffer) {
                    print("WARNING: Failed to append audio sample")
                    break
                }
            } else {
                waitCount += 1
                if waitCount > maxWaits {
                    print("WARNING: Audio processing timed out waiting for writer")
                    break
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    private func createPixelBuffer(
        from pool: CVPixelBufferPool?,
        size: CGSize,
        enableAlpha: Bool
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?

        if let pool = pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        } else {
            let pixelFormat: OSType = enableAlpha ? kCVPixelFormatType_64RGBALE : kCVPixelFormatType_32BGRA

            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]

            CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(size.width),
                Int(size.height),
                pixelFormat,
                attributes as CFDictionary,
                &pixelBuffer
            )
        }

        return pixelBuffer
    }

    enum ProcessingError: LocalizedError {
        case noOutputURL
        case noVideoTrack
        case cannotAddReaderOutput
        case cannotAddWriterInput
        case readerFailed(String)
        case writerFailed(String)
        case appendFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noOutputURL:
                return "No output URL specified"
            case .noVideoTrack:
                return "No video track found in source file"
            case .cannotAddReaderOutput:
                return "Cannot add reader output"
            case .cannotAddWriterInput:
                return "Cannot add writer input"
            case .readerFailed(let error):
                return "Reader failed: \(error)"
            case .writerFailed(let error):
                return "Writer failed: \(error)"
            case .appendFailed:
                return "Failed to append frame"
            case .cancelled:
                return "Export was cancelled"
            }
        }
    }
}

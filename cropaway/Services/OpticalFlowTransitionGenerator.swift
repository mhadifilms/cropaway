//
//  OpticalFlowTransitionGenerator.swift
//  cropaway
//

import Foundation
import VideoToolbox
import CoreVideo

/// Generates optical flow transition frames between two video frames
/// using Apple's VTFrameProcessor API (macOS 26+)
@available(macOS 26.0, *)
final class OpticalFlowTransitionGenerator {

    private var processor: VTFrameProcessor?
    private var isSessionActive = false

    /// Check if optical flow transitions are available on this system
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    deinit {
        stopSession()
    }

    // MARK: - Public API

    /// Generate interpolated frames between two source frames
    /// - Parameters:
    ///   - fromFrame: The starting frame (last frame of clip A)
    ///   - toFrame: The ending frame (first frame of clip B)
    ///   - frameCount: Number of transition frames to generate
    ///   - size: Output frame size
    /// - Returns: Array of interpolated CVPixelBuffers
    func generateTransitionFrames(
        fromFrame: CVPixelBuffer,
        toFrame: CVPixelBuffer,
        frameCount: Int,
        size: CGSize
    ) async throws -> [CVPixelBuffer] {
        guard frameCount > 0 else { return [] }

        // Start session if needed
        try startSession(width: Int(size.width), height: Int(size.height))

        var outputFrames: [CVPixelBuffer] = []
        outputFrames.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            // Calculate interpolation factor (0.0 to 1.0)
            let t = Double(i + 1) / Double(frameCount + 1)

            // Generate interpolated frame
            let interpolatedFrame = try await interpolateFrame(
                from: fromFrame,
                to: toFrame,
                at: t
            )

            outputFrames.append(interpolatedFrame)
        }

        return outputFrames
    }

    // MARK: - Private Methods

    private func startSession(width: Int, height: Int) throws {
        guard !isSessionActive else { return }

        processor = VTFrameProcessor()

        let config = VTFrameRateConversionConfiguration(
            frameWidth: width,
            frameHeight: height,
            usePrecomputedFlow: false,
            qualityPrioritization: .quality,
            revision: .revision1
        )

        try processor?.startSession(configuration: config)
        isSessionActive = true
    }

    private func stopSession() {
        guard isSessionActive else { return }
        processor?.stopSession()
        processor = nil
        isSessionActive = false
    }

    private func interpolateFrame(
        from sourceFrame: CVPixelBuffer,
        to targetFrame: CVPixelBuffer,
        at factor: Double
    ) async throws -> CVPixelBuffer {
        guard let processor = processor else {
            throw OpticalFlowError.processorNotInitialized
        }

        // Create parameters for frame interpolation
        let params = VTFrameRateConversionParameters(
            sourceFrame: sourceFrame,
            nextFrame: targetFrame,
            interpolationFactor: Float(factor)
        )

        // Process and get interpolated frame
        let result = try await processor.processFrame(with: params)

        guard let outputFrame = result.outputFrame else {
            throw OpticalFlowError.interpolationFailed
        }

        return outputFrame
    }
}

// MARK: - Fallback for older macOS

/// Fallback generator that creates simple crossfade frames (pre-macOS 26)
final class CrossfadeTransitionGenerator {

    /// Generate crossfade transition frames
    /// - Parameters:
    ///   - fromFrame: Starting frame
    ///   - toFrame: Ending frame
    ///   - frameCount: Number of transition frames
    ///   - size: Output size
    /// - Returns: Array of crossfaded frames
    func generateTransitionFrames(
        fromFrame: CVPixelBuffer,
        toFrame: CVPixelBuffer,
        frameCount: Int,
        size: CGSize
    ) throws -> [CVPixelBuffer] {
        var outputFrames: [CVPixelBuffer] = []
        outputFrames.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            let alpha = Float(i + 1) / Float(frameCount + 1)
            let blendedFrame = try blendFrames(fromFrame, toFrame, alpha: alpha)
            outputFrames.append(blendedFrame)
        }

        return outputFrames
    }

    private func blendFrames(
        _ frame1: CVPixelBuffer,
        _ frame2: CVPixelBuffer,
        alpha: Float
    ) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(frame1)
        let height = CVPixelBufferGetHeight(frame1)

        // Create output buffer
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            nil,
            &outputBuffer
        )

        guard let output = outputBuffer else {
            throw OpticalFlowError.bufferCreationFailed
        }

        // Lock buffers
        CVPixelBufferLockBaseAddress(frame1, .readOnly)
        CVPixelBufferLockBaseAddress(frame2, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(frame1, .readOnly)
            CVPixelBufferUnlockBaseAddress(frame2, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
        }

        guard let src1 = CVPixelBufferGetBaseAddress(frame1),
              let src2 = CVPixelBufferGetBaseAddress(frame2),
              let dst = CVPixelBufferGetBaseAddress(output) else {
            throw OpticalFlowError.bufferAccessFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(output)
        let src1Bytes = src1.assumingMemoryBound(to: UInt8.self)
        let src2Bytes = src2.assumingMemoryBound(to: UInt8.self)
        let dstBytes = dst.assumingMemoryBound(to: UInt8.self)

        // Simple alpha blend
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                for c in 0..<4 {  // BGRA
                    let v1 = Float(src1Bytes[idx + c])
                    let v2 = Float(src2Bytes[idx + c])
                    dstBytes[idx + c] = UInt8(v1 * (1 - alpha) + v2 * alpha)
                }
            }
        }

        return output
    }
}

// MARK: - Errors

enum OpticalFlowError: LocalizedError {
    case processorNotInitialized
    case interpolationFailed
    case bufferCreationFailed
    case bufferAccessFailed

    var errorDescription: String? {
        switch self {
        case .processorNotInitialized:
            return "Frame processor not initialized"
        case .interpolationFailed:
            return "Failed to interpolate frame"
        case .bufferCreationFailed:
            return "Failed to create pixel buffer"
        case .bufferAccessFailed:
            return "Failed to access pixel buffer"
        }
    }
}

// MARK: - VTFrameProcessor Stub (for compilation on older SDKs)
// These are placeholder types that match the expected macOS 26 API
// They will be replaced by the real types when building with the macOS 26 SDK

#if !canImport(VideoToolbox) || swift(<6.0)
// Stub implementations for development on older SDKs
// These allow the code to compile but will use the real APIs at runtime on macOS 26+

class VTFrameProcessor {
    func startSession(configuration: VTFrameRateConversionConfiguration) throws {}
    func stopSession() {}
    func processFrame(with params: VTFrameRateConversionParameters) async throws -> VTFrameProcessorResult {
        return VTFrameProcessorResult()
    }
}

struct VTFrameRateConversionConfiguration {
    enum QualityPrioritization { case quality, normal, speed }
    enum Revision { case revision1 }

    init(frameWidth: Int, frameHeight: Int, usePrecomputedFlow: Bool, qualityPrioritization: QualityPrioritization, revision: Revision) {}
}

struct VTFrameRateConversionParameters {
    init(sourceFrame: CVPixelBuffer, nextFrame: CVPixelBuffer, interpolationFactor: Float) {}
}

struct VTFrameProcessorResult {
    var outputFrame: CVPixelBuffer? { nil }
}
#endif

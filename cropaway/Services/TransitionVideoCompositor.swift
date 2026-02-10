//
//  TransitionVideoCompositor.swift
//  cropaway
//

import Foundation
import AVFoundation
import CoreVideo
import Accelerate

/// Custom video compositor for rendering transitions in real-time
/// Implements AVVideoCompositing protocol to blend frames during playback
final class TransitionVideoCompositor: NSObject, AVVideoCompositing {
    
    private let renderQueue = DispatchQueue(label: "com.cropaway.transitionCompositor", qos: .userInteractive)
    private var renderContext: AVVideoCompositionRenderContext?
    
    // MARK: - AVVideoCompositing Protocol
    
    var sourcePixelBufferAttributes: [String : Any]? {
        return [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
            String(kCVPixelBufferOpenGLCompatibilityKey): true
        ]
    }
    
    var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        return [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
            String(kCVPixelBufferOpenGLCompatibilityKey): true
        ]
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderQueue.sync {
            renderContext = newRenderContext
        }
    }
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            guard let self = self else {
                request.finish(with: NSError(domain: "TransitionVideoCompositor", code: -1))
                return
            }
            
            // Check if this is a custom transition instruction
            guard let instruction = request.videoCompositionInstruction as? TransitionCompositionInstruction else {
                // Not a custom instruction, just pass through
                if let sourceFrame = request.sourceFrame(byTrackID: kCMPersistentTrackID_Invalid) {
                    request.finish(withComposedVideoFrame: sourceFrame)
                } else {
                    request.finish(with: NSError(domain: "TransitionVideoCompositor", code: -2))
                }
                return
            }
            
            // Render transition based on type
            switch instruction.transitionType {
            case .cut:
                // Should never happen - cuts don't use custom compositor
                self.renderPassthrough(request: request, instruction: instruction)
                
            case .fade:
                self.renderFade(request: request, instruction: instruction)
                
            case .fadeToBlack:
                self.renderFadeToBlack(request: request, instruction: instruction)
                
            case .opticalFlow:
                // For playback, fall back to fade (optical flow only for export)
                self.renderFade(request: request, instruction: instruction)
            }
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {
        // Nothing to cancel in this simple implementation
    }
    
    // MARK: - Rendering Methods
    
    /// Pass through the appropriate source frame
    private func renderPassthrough(
        request: AVAsynchronousVideoCompositionRequest,
        instruction: TransitionCompositionInstruction
    ) {
        // For cut, just show the incoming clip
        if let toFrame = request.sourceFrame(byTrackID: instruction.toTrackID) {
            request.finish(withComposedVideoFrame: toFrame)
        } else if let fromFrame = request.sourceFrame(byTrackID: instruction.fromTrackID) {
            request.finish(withComposedVideoFrame: fromFrame)
        } else {
            request.finish(with: NSError(domain: "TransitionVideoCompositor", code: -3))
        }
    }
    
    /// Render cross-dissolve transition
    private func renderFade(
        request: AVAsynchronousVideoCompositionRequest,
        instruction: TransitionCompositionInstruction
    ) {
        // Get source frames
        guard let fromPixelBuffer = request.sourceFrame(byTrackID: instruction.fromTrackID),
              let toPixelBuffer = request.sourceFrame(byTrackID: instruction.toTrackID) else {
            // If we can't get both frames, fall back to passthrough
            renderPassthrough(request: request, instruction: instruction)
            return
        }
        
        // Calculate progress through transition (0.0 to 1.0)
        let currentTime = request.compositionTime
        let transitionStart = instruction.timeRange.start
        let transitionDuration = instruction.timeRange.duration
        
        let elapsed = CMTimeSubtract(currentTime, transitionStart)
        let progress = elapsed.seconds / transitionDuration.seconds
        let clampedProgress = max(0.0, min(1.0, progress))
        
        // Create output buffer
        guard let renderContext = renderContext,
              let outputBuffer = renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "TransitionVideoCompositor", code: -4))
            return
        }
        
        // Blend frames
        let blendSuccess = blendFrames(
            from: fromPixelBuffer,
            to: toPixelBuffer,
            output: outputBuffer,
            alpha: Float(clampedProgress)
        )
        
        if blendSuccess {
            request.finish(withComposedVideoFrame: outputBuffer)
        } else {
            request.finish(with: NSError(domain: "TransitionVideoCompositor", code: -5))
        }
    }
    
    /// Render fade to black transition (two-stage: fade out, then fade in)
    private func renderFadeToBlack(
        request: AVAsynchronousVideoCompositionRequest,
        instruction: TransitionCompositionInstruction
    ) {
        // Calculate progress through transition
        let currentTime = request.compositionTime
        let transitionStart = instruction.timeRange.start
        let transitionDuration = instruction.timeRange.duration
        
        let elapsed = CMTimeSubtract(currentTime, transitionStart)
        let progress = elapsed.seconds / transitionDuration.seconds
        let clampedProgress = max(0.0, min(1.0, progress))
        
        // Create output buffer
        guard let renderContext = renderContext,
              let outputBuffer = renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "TransitionVideoCompositor", code: -6))
            return
        }
        
        if clampedProgress < 0.5 {
            // First half: Fade out from clip to black
            guard let fromPixelBuffer = request.sourceFrame(byTrackID: instruction.fromTrackID) else {
                renderPassthrough(request: request, instruction: instruction)
                return
            }
            
            let fadeOutProgress = clampedProgress * 2.0  // 0.0 to 1.0 in first half
            let alpha = Float(1.0 - fadeOutProgress)  // 1.0 to 0.0
            
            let blendSuccess = blendWithBlack(
                source: fromPixelBuffer,
                output: outputBuffer,
                alpha: alpha
            )
            
            if blendSuccess {
                request.finish(withComposedVideoFrame: outputBuffer)
            } else {
                request.finish(with: NSError(domain: "TransitionVideoCompositor", code: -7))
            }
            
        } else {
            // Second half: Fade in from black to next clip
            guard let toPixelBuffer = request.sourceFrame(byTrackID: instruction.toTrackID) else {
                renderPassthrough(request: request, instruction: instruction)
                return
            }
            
            let fadeInProgress = (clampedProgress - 0.5) * 2.0  // 0.0 to 1.0 in second half
            let alpha = Float(fadeInProgress)  // 0.0 to 1.0
            
            let blendSuccess = blendWithBlack(
                source: toPixelBuffer,
                output: outputBuffer,
                alpha: alpha
            )
            
            if blendSuccess {
                request.finish(withComposedVideoFrame: outputBuffer)
            } else {
                request.finish(with: NSError(domain: "TransitionVideoCompositor", code: -8))
            }
        }
    }
    
    // MARK: - Frame Blending Utilities
    
    /// Blend two frames with linear interpolation
    /// - Parameters:
    ///   - from: Source frame (fade from)
    ///   - to: Destination frame (fade to)
    ///   - output: Output buffer
    ///   - alpha: Blend factor (0.0 = all from, 1.0 = all to)
    /// - Returns: True if blending succeeded
    private func blendFrames(
        from: CVPixelBuffer,
        to: CVPixelBuffer,
        output: CVPixelBuffer,
        alpha: Float
    ) -> Bool {
        CVPixelBufferLockBaseAddress(from, .readOnly)
        CVPixelBufferLockBaseAddress(to, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(to, .readOnly)
            CVPixelBufferUnlockBaseAddress(from, .readOnly)
        }
        
        let width = CVPixelBufferGetWidth(output)
        let height = CVPixelBufferGetHeight(output)
        
        guard let fromBytes = CVPixelBufferGetBaseAddress(from),
              let toBytes = CVPixelBufferGetBaseAddress(to),
              let outBytes = CVPixelBufferGetBaseAddress(output) else {
            return false
        }
        
        let fromBytesPerRow = CVPixelBufferGetBytesPerRow(from)
        let toBytesPerRow = CVPixelBufferGetBytesPerRow(to)
        let outBytesPerRow = CVPixelBufferGetBytesPerRow(output)
        
        let fromPointer = fromBytes.assumingMemoryBound(to: UInt8.self)
        let toPointer = toBytes.assumingMemoryBound(to: UInt8.self)
        let outPointer = outBytes.assumingMemoryBound(to: UInt8.self)
        
        // Blend each pixel: output = from * (1-alpha) + to * alpha
        for y in 0..<height {
            for x in 0..<width {
                let fromIdx = y * fromBytesPerRow + x * 4
                let toIdx = y * toBytesPerRow + x * 4
                let outIdx = y * outBytesPerRow + x * 4
                
                // Blend BGRA channels
                for channel in 0..<4 {
                    let fromVal = Float(fromPointer[fromIdx + channel])
                    let toVal = Float(toPointer[toIdx + channel])
                    let blended = fromVal * (1.0 - alpha) + toVal * alpha
                    outPointer[outIdx + channel] = UInt8(blended)
                }
            }
        }
        
        return true
    }
    
    /// Blend a frame with black
    /// - Parameters:
    ///   - source: Source frame
    ///   - output: Output buffer
    ///   - alpha: Opacity of source (0.0 = black, 1.0 = full source)
    /// - Returns: True if blending succeeded
    private func blendWithBlack(
        source: CVPixelBuffer,
        output: CVPixelBuffer,
        alpha: Float
    ) -> Bool {
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        
        let width = CVPixelBufferGetWidth(output)
        let height = CVPixelBufferGetHeight(output)
        
        guard let sourceBytes = CVPixelBufferGetBaseAddress(source),
              let outBytes = CVPixelBufferGetBaseAddress(output) else {
            return false
        }
        
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(source)
        let outBytesPerRow = CVPixelBufferGetBytesPerRow(output)
        
        let sourcePointer = sourceBytes.assumingMemoryBound(to: UInt8.self)
        let outPointer = outBytes.assumingMemoryBound(to: UInt8.self)
        
        // Blend each pixel with black: output = source * alpha
        for y in 0..<height {
            for x in 0..<width {
                let sourceIdx = y * sourceBytesPerRow + x * 4
                let outIdx = y * outBytesPerRow + x * 4
                
                // Blend BGRA channels (blend with 0 for black)
                for channel in 0..<4 {
                    let sourceVal = Float(sourcePointer[sourceIdx + channel])
                    let blended = sourceVal * alpha
                    outPointer[outIdx + channel] = UInt8(blended)
                }
            }
        }
        
        return true
    }
}

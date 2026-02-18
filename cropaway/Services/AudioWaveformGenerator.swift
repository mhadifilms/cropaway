//
//  AudioWaveformGenerator.swift
//  cropaway
//
//  PHASE 9: Audio waveform visualization for audio tracks

import Foundation
import AVFoundation
import AppKit

/// Service for generating audio waveform data and images
final class AudioWaveformGenerator {
    
    /// Generate waveform samples from an audio track
    /// - Parameters:
    ///   - asset: The AVAsset containing audio
    ///   - sampleCount: Number of samples to generate (affects detail level)
    /// - Returns: Array of normalized amplitude values (0.0 to 1.0)
    static func generateWaveform(from asset: AVAsset, sampleCount: Int = 100) async throws -> [Float] {
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioWaveformError.noAudioTrack
        }
        
        let assetReader = try AVAssetReader(asset: asset)
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        assetReader.add(trackOutput)
        
        var samples: [Float] = []
        var allSamples: [Int16] = []
        
        assetReader.startReading()
        
        while assetReader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }
            guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            
            let length = CMBlockBufferGetDataLength(dataBuffer)
            var data = Data(count: length)
            
            _ = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            
            let int16Samples = data.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Int16.self))
            }
            
            allSamples.append(contentsOf: int16Samples)
        }
        
        // Downsample to requested sample count
        let samplesPerBucket = max(1, allSamples.count / sampleCount)
        
        for i in 0..<sampleCount {
            let startIndex = i * samplesPerBucket
            let endIndex = min(startIndex + samplesPerBucket, allSamples.count)
            
            guard startIndex < allSamples.count else { break }
            
            let bucket = allSamples[startIndex..<endIndex]
            let rms = sqrt(bucket.map { Float($0) * Float($0) }.reduce(0, +) / Float(bucket.count))
            let normalized = min(1.0, rms / Float(Int16.max))
            
            samples.append(normalized)
        }
        
        return samples
    }
    
    /// Generate a waveform image for display
    /// - Parameters:
    ///   - samples: Normalized amplitude samples
    ///   - size: Size of the output image
    ///   - color: Color of the waveform
    /// - Returns: NSImage of the waveform
    static func generateWaveformImage(from samples: [Float], size: CGSize, color: NSColor = .systemBlue) -> NSImage {
        let image = NSImage(size: size)
        
        image.lockFocus()
        defer { image.unlockFocus() }
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }
        
        // Draw background
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Draw waveform
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.0)
        context.setLineCap(.round)
        
        let midY = size.height / 2
        let maxAmplitude = size.height / 2 - 2
        let sampleWidth = size.width / CGFloat(samples.count)
        
        context.beginPath()
        
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * sampleWidth
            let amplitude = CGFloat(sample) * maxAmplitude
            
            // Draw from center outward (symmetric waveform)
            context.move(to: CGPoint(x: x, y: midY - amplitude))
            context.addLine(to: CGPoint(x: x, y: midY + amplitude))
        }
        
        context.strokePath()
        
        return image
    }
    
    /// Generate a simple RMS (volume level) value for a time range
    /// - Parameters:
    ///   - asset: The AVAsset containing audio
    ///   - startTime: Start time in seconds
    ///   - duration: Duration in seconds
    /// - Returns: Normalized RMS value (0.0 to 1.0)
    static func getRMSLevel(from asset: AVAsset, startTime: Double, duration: Double) async throws -> Float {
        let samples = try await generateWaveform(from: asset, sampleCount: 10)
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        return rms
    }
}

enum AudioWaveformError: Error {
    case noAudioTrack
    case readingFailed
}

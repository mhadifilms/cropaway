//
//  AISegmentation.swift
//  cropaway
//

import Foundation
import CoreGraphics
import CoreImage

/// AI interaction mode for segmentation
enum AIInteractionMode: String, CaseIterable, Identifiable, Codable {
    case point = "point"    // Click point prompt (default)
    case text = "text"      // Text prompt ("select the person")

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .point: return "Point"
        }
    }

    var iconName: String {
        switch self {
        case .text: return "text.cursor"
        case .point: return "hand.point.up.left"
        }
    }

    var description: String {
        switch self {
        case .text: return "Enter text to describe what to select"
        case .point: return "Click on the object to track"
        }
    }
}

/// A point prompt for AI segmentation (click to include/exclude)
struct AIPromptPoint: Codable, Identifiable, Equatable {
    let id: UUID
    var position: CGPoint      // Normalized 0-1 coordinates
    var isPositive: Bool       // true = include region, false = exclude region

    init(position: CGPoint, isPositive: Bool = true) {
        self.id = UUID()
        self.position = position
        self.isPositive = isPositive
    }

    /// Label: 1 for foreground (positive), 0 for background (negative)
    var label: Int {
        isPositive ? 1 : 0
    }
}

/// Result from AI segmentation
struct AIMaskResult: Codable, Equatable {
    var maskData: Data         // RLE-encoded binary mask
    var boundingBox: CGRect    // Object bounding box (normalized 0-1)
    var confidence: Double     // Segmentation confidence score (0-1)
    var objectId: String       // Unique ID for tracking continuity

    init(maskData: Data, boundingBox: CGRect, confidence: Double, objectId: String = UUID().uuidString) {
        self.maskData = maskData
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.objectId = objectId
    }
}

/// Direction for video tracking
enum TrackDirection {
    case forward
    case backward
}

// MARK: - RLE Mask Utilities

extension AIMaskResult {
    /// Decode RLE mask data to a bitmap (returns CGImage for proper handling of dimensions)
    ///
    /// Supports multiple RLE formats:
    /// 1. fal.ai SAM3 video-rle format: space-separated (start, length) pairs in row-major order
    /// 2. COCO RLE format: alternating background/foreground counts in column-major order
    /// 3. COCO compressed RLE: LEB128-like encoded string
    static func decodeMaskToImage(_ data: Data) -> (CGImage, Int, Int)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "binary"
            print("[AIMaskResult] Error: Failed to parse RLE JSON. Data preview: \(preview)")
            return nil
        }

        guard let rleSize = json["size"] as? [Int], rleSize.count == 2 else {
            print("[AIMaskResult] Error: RLE missing 'size' field. Keys present: \(json.keys)")
            return nil
        }

        let h = rleSize[0]  // height
        let w = rleSize[1]  // width
        let totalPixels = h * w
        print("[AIMaskResult] Decoding RLE mask: \(w)x\(h) (\(totalPixels) pixels)")

        // Get counts - either as array of ints or string format
        let countsValue = json["counts"]

        // Check if this is fal.ai (start, length) pair format (space-separated string)
        if let countsString = countsValue as? String {
            // fal.ai SAM3 video-rle returns space-separated integers as (start, length) pairs
            // These are in ROW-MAJOR order (unlike COCO which is column-major)
            if let cgImage = decodeFalAIRLE(countsString, width: w, height: h) {
                return (cgImage, w, h)
            }

            // Fall back to COCO compressed RLE format
            if let cgImage = decodeCOCOCompressedRLE(countsString, width: w, height: h) {
                return (cgImage, w, h)
            }

            print("[AIMaskResult] Error: Failed to decode RLE string in any known format")
            return nil
        }

        // Standard COCO RLE with integer array counts
        if let countsArray = countsValue as? [Int] {
            if let cgImage = decodeCOCOIntegerRLE(countsArray, width: w, height: h) {
                return (cgImage, w, h)
            }
            print("[AIMaskResult] Error: Failed to decode COCO integer RLE")
            return nil
        }

        print("[AIMaskResult] Error: 'counts' field is neither array nor string")
        return nil
    }

    /// Decode fal.ai SAM3 video-rle format: space-separated (start, length) pairs
    /// Format: "start1 len1 start2 len2 ..." where indices are ROW-MAJOR (not column-major like COCO)
    private static func decodeFalAIRLE(_ rleString: String, width w: Int, height h: Int) -> CGImage? {
        // Parse space-separated integers
        let parts = rleString.split(separator: " ")
        let intValues = parts.compactMap { Int($0) }

        guard intValues.count > 0 && intValues.count == parts.count else {
            print("[AIMaskResult] Not a valid space-separated integer string")
            return nil
        }

        guard intValues.count % 2 == 0 else {
            print("[AIMaskResult] fal.ai RLE has odd number of values (\(intValues.count)), expected pairs")
            return nil
        }

        // Find the maximum pixel position to validate/detect resolution
        var maxPixel = 0
        var hasNegative = false

        for i in stride(from: 0, to: intValues.count, by: 2) {
            let start = intValues[i]
            let length = intValues[i + 1]

            if start < 0 { hasNegative = true }
            let end = start + length
            if end > maxPixel { maxPixel = end }
        }

        // Basic validity checks
        if hasNegative {
            print("[AIMaskResult] RLE has negative start values - invalid")
            return nil
        }

        // Determine actual dimensions to use
        var actualW = w
        var actualH = h
        let totalPixels = w * h

        // If max pixel exceeds declared size, the size might be wrong
        // Auto-detect dimensions based on common aspect ratios
        if maxPixel > totalPixels {
            print("[AIMaskResult] Max pixel (\(maxPixel)) exceeds declared size (\(w)x\(h)=\(totalPixels)), detecting actual size...")

            // Try common resolutions that match the video's aspect ratio
            let aspectRatio = Double(w) / Double(h)
            let commonWidths = [3840, 1920, 1280, 960, 854, 640]

            for testW in commonWidths {
                let testH = Int(Double(testW) / aspectRatio)
                if maxPixel <= testW * testH {
                    actualW = testW
                    actualH = testH
                    print("[AIMaskResult] Using detected size: \(actualW)x\(actualH)")
                    break
                }
            }
        }

        let actualTotal = actualW * actualH

        // Final validation
        if maxPixel > actualTotal {
            print("[AIMaskResult] Max pixel (\(maxPixel)) still exceeds \(actualW)x\(actualH)=\(actualTotal)")
            // Still try to decode, clamping out-of-bounds pixels
        }

        let totalPairs = intValues.count / 2
        print("[AIMaskResult] Decoding fal.ai format: \(totalPairs) (start, length) pairs for \(actualW)x\(actualH)")

        // Create mask bitmap - fal.ai uses ROW-MAJOR order (standard image order)
        var mask = [UInt8](repeating: 0, count: actualTotal)
        var foregroundPixels = 0

        for i in stride(from: 0, to: intValues.count, by: 2) {
            let start = intValues[i]
            let length = intValues[i + 1]

            // Skip invalid pairs
            guard start >= 0 && length > 0 else { continue }

            // Fill foreground pixels directly (row-major, no transpose needed)
            for j in 0..<length {
                let idx = start + j
                if idx >= 0 && idx < actualTotal {
                    mask[idx] = 255
                    foregroundPixels += 1
                }
            }
        }

        // Verify the mask was created correctly
        let actualForeground = mask.filter { $0 > 0 }.count
        print("[AIMaskResult] Decoded fal.ai RLE: \(foregroundPixels) foreground pixels (\(String(format: "%.1f", Double(foregroundPixels) / Double(actualTotal) * 100))% of \(actualTotal) total)")

        // Sanity check: foreground should be less than total pixels and match what we counted
        if actualForeground != foregroundPixels {
            print("[AIMaskResult] Warning: Pixel count mismatch - counted \(foregroundPixels) but mask has \(actualForeground)")
        }

        // Create CGImage from bitmap with detected dimensions
        return createGrayscaleCGImage(from: mask, width: actualW, height: actualH)
    }

    /// Decode COCO compressed RLE format (LEB128-like encoding with zigzag and delta)
    private static func decodeCOCOCompressedRLE(_ rleString: String, width w: Int, height h: Int) -> CGImage? {
        // COCO compressed format uses ASCII characters starting at '0' (ASCII 48)
        // Check if string contains only valid COCO RLE characters (printable ASCII)
        let validChars = CharacterSet(charactersIn: "0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmno")
        guard rleString.unicodeScalars.allSatisfy({ validChars.contains($0) }) else {
            return nil
        }

        var counts: [Int] = []
        var i = 0
        let chars = Array(rleString.utf8)

        while i < chars.count {
            var x = 0
            var k = 0
            var more = true

            while more && i < chars.count {
                let c = Int(chars[i]) - 48  // ASCII offset
                guard c >= 0 && c <= 63 else {
                    print("[AIMaskResult] Invalid COCO RLE character at position \(i)")
                    return nil
                }
                x |= (c & 0x1f) << (5 * k)
                more = (c & 0x20) != 0
                i += 1
                k += 1
            }

            // Zigzag decode
            if (x & 1) != 0 {
                x = -(x >> 1) - 1
            } else {
                x = x >> 1
            }

            // Delta decode (cumulative)
            if counts.isEmpty {
                counts.append(x)
            } else {
                counts.append(counts.last! + x)
            }
        }

        print("[AIMaskResult] Decoded \(counts.count) counts from COCO compressed RLE")

        return decodeCOCOIntegerRLE(counts, width: w, height: h)
    }

    /// Decode standard COCO RLE with integer array counts (column-major order)
    /// Format: alternating [bg_count, fg_count, bg_count, fg_count, ...]
    private static func decodeCOCOIntegerRLE(_ counts: [Int], width w: Int, height h: Int) -> CGImage? {
        let totalPixels = w * h

        // Validate counts sum
        let countsSum = counts.reduce(0) { $0 + max(0, $1) }
        if countsSum != totalPixels {
            print("[AIMaskResult] Warning: COCO RLE counts sum to \(countsSum), expected \(totalPixels)")
            // If way off, this might not be valid COCO format
            if countsSum > totalPixels * 2 || countsSum < totalPixels / 2 {
                print("[AIMaskResult] Counts sum is too far off, likely not COCO RLE format")
                return nil
            }
        }

        // COCO RLE is column-major (Fortran order)
        // We need to decode and transpose to row-major for CGImage
        var mask = [UInt8](repeating: 0, count: totalPixels)
        var colMajorIdx = 0
        var value: UInt8 = 0  // Start with background (0)

        for count in counts {
            let safeCount = max(0, count)
            for _ in 0..<safeCount {
                if colMajorIdx < totalPixels {
                    // Convert column-major index to row-major
                    let col = colMajorIdx / h
                    let row = colMajorIdx % h
                    let rowMajorIdx = row * w + col
                    if rowMajorIdx < mask.count {
                        mask[rowMajorIdx] = value
                    }
                    colMajorIdx += 1
                }
            }
            value = value == 0 ? 255 : 0  // Toggle between background and foreground
        }

        let foregroundPixels = mask.filter { $0 > 0 }.count
        print("[AIMaskResult] Decoded COCO RLE: \(foregroundPixels) foreground pixels")

        return createGrayscaleCGImage(from: mask, width: w, height: h)
    }

    /// Create a grayscale CGImage from a bitmap array
    /// This creates an image with alpha channel where the mask values become the alpha
    /// Applies a small amount of edge smoothing to reduce pixelated/jagged edges
    private static func createGrayscaleCGImage(from bitmap: [UInt8], width w: Int, height h: Int) -> CGImage? {
        // Create RGBA image where grayscale values become alpha channel
        // This is needed for CALayer masks which use alpha channel for masking
        var rgbaData = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let alpha = bitmap[i]
            rgbaData[i * 4 + 0] = 255      // R - white
            rgbaData[i * 4 + 1] = 255      // G - white
            rgbaData[i * 4 + 2] = 255      // B - white
            rgbaData[i * 4 + 3] = alpha    // A - mask value
        }

        guard let provider = CGDataProvider(data: Data(rgbaData) as CFData) else {
            return nil
        }

        guard let rawImage = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }

        // Apply edge smoothing using Core Image
        return applyEdgeSmoothing(to: rawImage)
    }

    /// Apply subtle edge smoothing to a mask image using Core Image filters
    /// This reduces jagged/pixelated edges from RLE-decoded masks without significantly changing the mask shape
    private static func applyEdgeSmoothing(to image: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: image)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Use a small Gaussian blur to smooth edges
        // Radius is calculated relative to image size for consistent results across resolutions
        // A blur of ~0.5-1.0 pixels is enough to anti-alias without losing detail
        let blurRadius = max(0.5, min(Double(image.width), Double(image.height)) / 1500.0)

        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            print("[AIMaskResult] Warning: Could not create blur filter, returning unsmoothed mask")
            return image
        }

        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)

        guard let blurredImage = blurFilter.outputImage else {
            print("[AIMaskResult] Warning: Blur filter produced no output, returning unsmoothed mask")
            return image
        }

        // Gaussian blur expands the image extent, so we need to crop back to original size
        let croppedImage = blurredImage.cropped(to: ciImage.extent)

        // Render the smoothed image back to CGImage
        guard let smoothedCGImage = context.createCGImage(croppedImage, from: ciImage.extent) else {
            print("[AIMaskResult] Warning: Could not render smoothed mask, returning unsmoothed mask")
            return image
        }

        print("[AIMaskResult] Applied edge smoothing with blur radius \(String(format: "%.2f", blurRadius))")
        return smoothedCGImage
    }

    /// Decode RLE mask data to a bitmap (legacy interface for compatibility)
    static func decodeMask(_ data: Data, width: Int, height: Int) -> [UInt8]? {
        guard let (cgImage, _, _) = decodeMaskToImage(data) else {
            // Try raw bitmap fallback
            if data.count == width * height {
                return [UInt8](data)
            }
            return nil
        }

        // Extract bitmap from CGImage
        let w = cgImage.width
        let h = cgImage.height
        var bitmap = [UInt8](repeating: 0, count: w * h)

        guard let context = CGContext(
            data: &bitmap,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bitmap
    }

    /// Encode a bitmap to RLE format
    static func encodeMask(_ bitmap: [UInt8], width: Int, height: Int) -> Data? {
        var counts: [Int] = []
        var currentValue: UInt8 = 0
        var currentCount = 0

        for pixel in bitmap {
            let value: UInt8 = pixel > 127 ? 255 : 0
            if value == currentValue {
                currentCount += 1
            } else {
                if currentCount > 0 {
                    counts.append(currentCount)
                }
                currentValue = value
                currentCount = 1
            }
        }
        if currentCount > 0 {
            counts.append(currentCount)
        }

        let rle: [String: Any] = [
            "counts": counts,
            "size": [height, width]
        ]

        return try? JSONSerialization.data(withJSONObject: rle)
    }
}

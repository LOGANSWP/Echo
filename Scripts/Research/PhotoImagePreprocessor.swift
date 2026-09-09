// Task 4.0l / ADR-025: bounded native pixel preprocessing research, outside the App.
import CoreGraphics
import Foundation
import ImageIO

enum PhotoImageError: Error { case invalidInput, resourceLimit, decode }

struct PreparedPhoto: Sendable {
    let width: Int
    let height: Int
    let pixels: [Float]
    let positionIDs: [Int32]
    let attentionMask: [Float]
}

enum PhotoImagePreprocessor {
    static func prepare(_ encoded: Data) throws -> PreparedPhoto {
        guard !encoded.isEmpty else { throw PhotoImageError.invalidInput }
        guard encoded.count <= 32_000_000 else { throw PhotoImageError.resourceLimit }
        guard let source = CGImageSourceCreateWithData(encoded as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw PhotoImageError.invalidInput }
        guard width <= 16_384, height <= 16_384, width * height <= 100_000_000 else {
            throw PhotoImageError.resourceLimit
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(512, max(width, height)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              (1...512).contains(image.width), (1...512).contains(image.height) else {
            throw PhotoImageError.decode
        }
        return try rasterize(image)
    }

    private static func rasterize(_ image: CGImage) throws -> PreparedPhoto {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let succeeded = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let color = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: color,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // Composite transparency explicitly; orientation was already applied by ImageIO.
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard succeeded else { throw PhotoImageError.decode }
        // Pad only after normalization, matching the reference model's neutral zero padding.
        var pixels = [Float](repeating: 0, count: 3 * 512 * 512)
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    pixels[channel * 512 * 512 + y * 512 + x] =
                        (Float(rgba[(y * width + x) * 4 + channel]) / 255 - 0.5) / 0.5
                }
            }
        }
        let rows = (height + 15) / 16, columns = (width + 15) / 16
        var positionIDs = [Int32](repeating: 0, count: 1024)
        var mask = [Float](repeating: -10000, count: 1024)
        for y in 0..<rows {
            for x in 0..<columns {
                positionIDs[y * 32 + x] = Int32((y * 32 / rows) * 32 + x * 32 / columns)
                mask[y * 32 + x] = 0
            }
        }
        return PreparedPhoto(width: width, height: height, pixels: pixels, positionIDs: positionIDs, attentionMask: mask)
    }
}

// Task 4.0l: native orientation/shape/mask and invalid-input tests; no saved media.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

enum ImageProbeError: Error { case fixture, mismatch(String) }

func encodedTestImage(width: Int, height: Int, orientation: Int) throws -> Data {
    var rgb = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let channel = (x < width / 2 ? 0 : 1)
            for c in 0..<3 { rgb[(y * width + x) * 4 + c] = c == channel ? 255 : 0 }
        }
    }
    guard let provider = CGDataProvider(data: Data(rgb) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw ImageProbeError.fixture }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil)
    else { throw ImageProbeError.fixture }
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw ImageProbeError.fixture }
    return data as Data
}

@main
enum PhotoImageProbe {
    static func main() {
        do {
            var count = 0
            for orientation in 1...8 {
                let prepared = try PhotoImagePreprocessor.prepare(encodedTestImage(width: 512, height: 256, orientation: orientation))
                let rotated = orientation >= 5
                guard prepared.width == (rotated ? 256 : 512), prepared.height == (rotated ? 512 : 256),
                      prepared.pixels.count == 3 * 512 * 512,
                      prepared.positionIDs.count == 1024, prepared.attentionMask.count == 1024,
                      prepared.attentionMask.filter({ $0 == 0 }).count == 512,
                      prepared.pixels.allSatisfy({ $0.isFinite && (-1...1).contains($0) })
                else { throw ImageProbeError.mismatch("shape/orientation \(orientation)") }
                // TIFF orientation: mirrored/rotated strips must land at the expected edge.
                let firstIsRed = [1, 4, 5, 6].contains(orientation)
                let r = prepared.pixels[10 * 512 + 10]
                let g = prepared.pixels[512 * 512 + 10 * 512 + 10]
                guard firstIsRed ? r > 0.9 && g < -0.9 : g > 0.9 && r < -0.9 else {
                    throw ImageProbeError.mismatch("orientation pixels \(orientation): \(r),\(g)")
                }
                count += 1
            }
            for (w, h) in [(1600, 900), (900, 1600), (512, 512), (17, 31)] {
                let result = try PhotoImagePreprocessor.prepare(encodedTestImage(width: w, height: h, orientation: 1))
                guard result.width <= 512, result.height <= 512,
                      abs(Double(result.width) / Double(result.height) - Double(w) / Double(h)) < 0.03
                else { throw ImageProbeError.mismatch("resize \(w)x\(h)") }
                let rows = (result.height + 15) / 16, columns = (result.width + 15) / 16
                for y in 0..<32 {
                    for x in 0..<32 {
                        let valid = y < rows && x < columns
                        guard result.attentionMask[y*32+x] == (valid ? 0 : -10000),
                              result.positionIDs[y*32+x] == (valid ? Int32((y*32/rows)*32+x*32/columns) : 0)
                        else { throw ImageProbeError.mismatch("patch mask") }
                    }
                }
                count += 1
            }
            var rejected = 0
            for bytes in [Data(), Data("not an image".utf8), Data(repeating: 0, count: 32_000_001)] {
                do { _ = try PhotoImagePreprocessor.prepare(bytes) }
                catch { rejected += 1 }
            }
            guard rejected == 3 else { throw ImageProbeError.mismatch("invalid input accepted") }
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["imageCasesPassed": count, "invalidInputsRejected": rejected]))
        } catch {
            FileHandle.standardError.write(Data("Image preprocessing failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}

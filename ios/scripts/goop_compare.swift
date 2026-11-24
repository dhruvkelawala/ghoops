import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func load(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "goop-compare", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read image: \(path)"])
    }
    return image
}

guard CommandLine.arguments.count == 4 else { fatalError("Usage: goop_compare.swift <mock.png> <screenshot.png> <output.png>") }
let mock = try load(CommandLine.arguments[1])
let shot = try load(CommandLine.arguments[2])
let width = 2380
let mockHeight = Int((Double(mock.height) * 1170 / Double(mock.width)).rounded())
let shotHeight = Int((Double(shot.height) * 1170 / Double(shot.width)).rounded())
let height = max(mockHeight, shotHeight)
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(srgbRed: 15.0 / 255, green: 17.0 / 255, blue: 19.0 / 255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
context.interpolationQuality = .high
context.draw(mock, in: CGRect(x: 0, y: height - mockHeight, width: 1170, height: mockHeight))
context.draw(shot, in: CGRect(x: 1210, y: height - shotHeight, width: 1170, height: shotHeight))
let output = URL(fileURLWithPath: CommandLine.arguments[3])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write comparison") }
print("wrote \(output.path) \(width)x\(height)")

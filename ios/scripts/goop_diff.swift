import Foundation
import CoreGraphics
import ImageIO

struct Raster {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "goop-diff", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read \(url.path)"])
        }
        width = image.width
        height = image.height
        pixels = Array(repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func image() -> CGImage {
        let data = Data(pixels) as CFData
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }
}

func captures(_ directory: URL) throws -> Set<String> {
    let raw = #"^(?:.*_\d+_)?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.png$"#
    return Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
        $0.hasSuffix(".png") && $0.range(of: raw, options: .regularExpression) == nil
    })
}

func comparison(_ before: Raster, _ after: Raster, _ marked: Raster, to url: URL) throws {
    let panelWidth = 402
    let panelHeight = Int((Double(before.height) * Double(panelWidth) / Double(before.width)).rounded())
    let width = panelWidth * 3 + 40
    let context = CGContext(data: nil, width: width, height: panelHeight, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 15.0 / 255, green: 17.0 / 255, blue: 19.0 / 255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: panelHeight))
    context.interpolationQuality = .high
    for (index, raster) in [before, after, marked].enumerated() {
        context.draw(raster.image(), in: CGRect(x: index * (panelWidth + 20), y: 0, width: panelWidth, height: panelHeight))
    }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "goop-diff", code: 2)
    }
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "goop-diff", code: 3) }
}

var arguments = Array(CommandLine.arguments.dropFirst())
var excluded: Set<String> = []
if arguments.first == "--exclude-file", arguments.count >= 2 {
    let contents = try String(contentsOfFile: arguments[1], encoding: .utf8)
    excluded = Set(contents.split(whereSeparator: \.isNewline).map {
        $0.split(separator: "#", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    }.filter { !$0.isEmpty })
    arguments.removeFirst(2)
}
guard arguments.count == 3 else {
    fatalError("Usage: goop_diff.swift [--exclude-file <path>] <before-dir> <after-dir> <out-dir>")
}
let beforeDirectory = URL(fileURLWithPath: arguments[0])
let afterDirectory = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let beforeNames = try captures(beforeDirectory)
let afterNames = try captures(afterDirectory)
var report: [String] = []
for name in beforeNames.union(afterNames).sorted() {
    let line: String
    if excluded.contains(name) {
        line = "EXCLUDED \(name)"
    } else if !beforeNames.contains(name) {
        line = "MISSING-BEFORE \(name)"
    } else if !afterNames.contains(name) {
        line = "MISSING-AFTER \(name)"
    } else {
        let before = try Raster(beforeDirectory.appendingPathComponent(name))
        let after = try Raster(afterDirectory.appendingPathComponent(name))
        if before.width != after.width || before.height != after.height {
            line = "SIZE \(name) \(before.width)x\(before.height) \(after.width)x\(after.height)"
        } else {
            var marked = after
            var count = 0
            var minX = before.width, minY = before.height, maxX = 0, maxY = 0
            before.pixels.withUnsafeBufferPointer { b in
                after.pixels.withUnsafeBufferPointer { a in
                    marked.pixels.withUnsafeMutableBufferPointer { m in
                        let first = min(162, before.height) * before.width * 4
                        if memcmp(b.baseAddress! + first, a.baseAddress! + first, b.count - first) == 0 { return }
                        for y in min(162, before.height)..<before.height {
                            let row = y * before.width * 4
                            if memcmp(b.baseAddress! + row, a.baseAddress! + row, before.width * 4) == 0 { continue }
                            for x in 0..<before.width {
                                let offset = row + x * 4
                                if b[offset] != a[offset] || b[offset + 1] != a[offset + 1] || b[offset + 2] != a[offset + 2] || b[offset + 3] != a[offset + 3] {
                                    count += 1
                                    minX = min(minX, x); minY = min(minY, y)
                                    maxX = max(maxX, x); maxY = max(maxY, y)
                                    m[offset] = 255; m[offset + 1] = 0; m[offset + 2] = 255; m[offset + 3] = 255
                                }
                            }
                        }
                    }
                }
            }
            if count == 0 {
                line = "SAME \(name)"
            } else {
                let x = minX / 3, y = minY / 3
                let width = (maxX + 3) / 3 - x, height = (maxY + 3) / 3 - y
                line = "DIFF \(name) pixels=\(count) box=\(x),\(y),\(width),\(height)"
                let stem = String(name.dropLast(4))
                try comparison(before, after, marked, to: output.appendingPathComponent("\(stem)-diff.png"))
            }
        }
    }
    report.append(line)
    print(line)
}
try (report.joined(separator: "\n") + "\n").write(to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)

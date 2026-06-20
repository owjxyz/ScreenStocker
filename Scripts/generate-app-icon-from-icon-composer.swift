import AppKit
import Foundation

struct IconComposerDocument {
    let sourceImageData: Data
    let layerColor: NSColor
    let backgroundColor: NSColor
}

enum IconGenerationError: Error, CustomStringConvertible {
    case missingArgument(String)
    case invalidDocument(URL)
    case missingAsset(String)
    case imageLoadFailed(URL)
    case imageWriteFailed(URL)

    var description: String {
        switch self {
        case .missingArgument(let name):
            return "Missing required argument: \(name)"
        case .invalidDocument(let url):
            return "Could not read Icon Composer document at \(url.path)"
        case .missingAsset(let name):
            return "Icon Composer document references a missing asset: \(name)"
        case .imageLoadFailed(let url):
            return "Could not load image asset at \(url.path)"
        case .imageWriteFailed(let url):
            return "Could not write generated icon at \(url.path)"
        }
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    throw IconGenerationError.missingArgument("icon-document-path appiconset-path")
}

let iconDocumentURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
let appIconSetURL = URL(fileURLWithPath: arguments[2], isDirectory: true)

func color(from encoded: String?) -> NSColor? {
    guard let encoded else { return nil }
    let parts = encoded.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    let components = parts[1]
        .split(separator: ",")
        .compactMap { Double($0) }

    if parts[0] == "extended-gray", components.count >= 2 {
        return NSColor(white: components[0], alpha: components[1])
    }

    if parts[0] == "display-p3", components.count >= 4 {
        return NSColor(
            displayP3Red: components[0],
            green: components[1],
            blue: components[2],
            alpha: components[3]
        )
    }

    return nil
}

func hexColor(from color: NSColor) -> String {
    let rgbColor = color.usingColorSpace(.sRGB) ?? color
    let red = max(0, min(255, Int(round(rgbColor.redComponent * 255))))
    let green = max(0, min(255, Int(round(rgbColor.greenComponent * 255))))
    let blue = max(0, min(255, Int(round(rgbColor.blueComponent * 255))))
    return String(format: "#%02X%02X%02X", red, green, blue)
}

func imageData(at url: URL, tinted color: NSColor) throws -> Data {
    let data = try Data(contentsOf: url)
    guard
        url.pathExtension.lowercased() == "svg",
        var svg = String(data: data, encoding: .utf8)
    else {
        return data
    }

    let fillPattern = ##"fill="#[0-9A-Fa-f]{6}""##
    let fillReplacement = #"fill="\#(hexColor(from: color))""#
    if let regex = try? NSRegularExpression(pattern: fillPattern) {
        svg = regex.stringByReplacingMatches(
            in: svg,
            range: NSRange(svg.startIndex..., in: svg),
            withTemplate: fillReplacement
        )
    }

    return Data(svg.utf8)
}

func loadDocument(at url: URL) throws -> IconComposerDocument {
    let jsonURL = url.appendingPathComponent("icon.json")
    guard
        let data = try? Data(contentsOf: jsonURL),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw IconGenerationError.invalidDocument(url)
    }

    let backgroundColor = ((object["fill"] as? [String: Any])
        .flatMap { color(from: $0["automatic-gradient"] as? String) }) ?? .white

    let groups = object["groups"] as? [[String: Any]] ?? []
    for group in groups {
        let layers = group["layers"] as? [[String: Any]] ?? []
        for layer in layers where (layer["hidden"] as? Bool) != true {
            guard let imageName = layer["image-name"] as? String else { continue }
            let fillSpecializations = layer["fill-specializations"] as? [[String: Any]] ?? []
            let layerColor = fillSpecializations
                .compactMap { specialization -> NSColor? in
                    guard specialization["appearance"] == nil else { return nil }
                    let value = specialization["value"] as? [String: Any]
                    return color(from: value?["solid"] as? String)
                }
                .first ?? .labelColor

            let sourceImageURL = url
                .appendingPathComponent("Assets", isDirectory: true)
                .appendingPathComponent(imageName)

            guard FileManager.default.fileExists(atPath: sourceImageURL.path) else {
                throw IconGenerationError.missingAsset(imageName)
            }

            return IconComposerDocument(
                sourceImageData: try imageData(at: sourceImageURL, tinted: layerColor),
                layerColor: layerColor,
                backgroundColor: backgroundColor
            )
        }
    }

    throw IconGenerationError.invalidDocument(url)
}

func renderIcon(document: IconComposerDocument, pixelSize: Int, outputURL: URL) throws {
    guard let sourceImage = NSImage(data: document.sourceImageData) else {
        throw IconGenerationError.imageLoadFailed(outputURL)
    }

    let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        throw IconGenerationError.imageWriteFailed(outputURL)
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    document.backgroundColor.setFill()
    rect.fill()
    sourceImage.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.imageWriteFailed(outputURL)
    }

    try pngData.write(to: outputURL)
}

let document = try loadDocument(at: iconDocumentURL)
let icons: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, pixelSize) in icons {
    try renderIcon(
        document: document,
        pixelSize: pixelSize,
        outputURL: appIconSetURL.appendingPathComponent(filename)
    )
}

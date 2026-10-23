#!/usr/bin/env swift
/// generate-icon.swift — Generates AppIcon PNG assets for all required macOS sizes.
///
/// Usage: swift generate-icon.swift <output-dir>
/// The output directory should be SHH/Assets.xcassets/AppIcon.appiconset/
///
/// Renders the exact same orange squircle + mark icon as AppDelegate.makeAppIcon().
/// The mark is read from SHH/Assets.xcassets/AppMark.imageset/AppMark.png.
import AppKit
import CoreGraphics
import ImageIO

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift generate-icon.swift <output-dir>\n", stderr)
    exit(1)
}
let outputDir = CommandLine.arguments[1]

let markPath = URL(fileURLWithPath: #filePath).absoluteURL
    .deletingLastPathComponent()
    .appendingPathComponent("../SHH/Assets.xcassets/AppMark.imageset/AppMark.png")
    .standardized.path
guard let markSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: markPath) as CFURL, nil),
      let markImage = CGImageSourceCreateImageAtIndex(markSource, 0, nil) else {
    fputs("Could not load the app mark at \(markPath)\n", stderr)
    exit(1)
}

// MARK: - Icon sizes required by macOS app icon asset catalog

struct IconSize {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String {
        scale == 2 ? "AppIcon_\(points)x\(points)@2x.png" : "AppIcon_\(points)x\(points).png"
    }
}

let sizes: [IconSize] = [
    .init(points: 16,  scale: 1), .init(points: 16,  scale: 2),
    .init(points: 32,  scale: 1), .init(points: 32,  scale: 2),
    .init(points: 128, scale: 1), .init(points: 128, scale: 2),
    .init(points: 256, scale: 1), .init(points: 256, scale: 2),
    .init(points: 512, scale: 1), .init(points: 512, scale: 2),
]

// MARK: - Drawing

/// Mark height as a fraction of the squircle's height.
let markHeightRatio: CGFloat = 0.56

func makeIcon(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { fatalError("Failed to create CGContext at \(pixels)px") }

    // Scale factor relative to the 1024-pt reference canvas
    let scale = size / 1024.0
    let inset   = 100.0 * scale
    let iconRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius  = 185.0 * scale

    // Background squircle (orange)
    ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(CGColor(red: 233/255.0, green: 79/255.0, blue: 55/255.0, alpha: 1.0))
    ctx.fillPath()

    // Mark, tinted cream: draw its alpha, then paint the colour through it.
    let markH = iconRect.height * markHeightRatio
    let markW = markH * CGFloat(markImage.width) / CGFloat(markImage.height)
    let markRect = CGRect(
        x: iconRect.midX - markW / 2,
        y: iconRect.midY - markH / 2,
        width: markW, height: markH
    )
    ctx.interpolationQuality = .high
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.draw(markImage, in: markRect)
    ctx.setBlendMode(.sourceIn)
    ctx.setFillColor(CGColor(red: 246/255.0, green: 247/255.0, blue: 235/255.0, alpha: 1.0))
    ctx.fill(markRect)
    ctx.endTransparencyLayer()

    guard let result = ctx.makeImage() else { fatalError("Failed to create CGImage at \(pixels)px") }
    return result
}

// MARK: - Save PNG

func savePNG(_ cgImage: CGImage, to path: String) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL,
        "public.png" as CFString, 1, nil
    ) else { throw NSError(domain: "IconGen", code: 2) }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "IconGen", code: 3) }
}

// MARK: - Generate

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

var jsonImages: [String] = []

for size in sizes {
    let img = makeIcon(pixels: size.pixels)
    let path = (outputDir as NSString).appendingPathComponent(size.filename)
    do {
        try savePNG(img, to: path)
        print("  ✓ \(size.filename)  (\(size.pixels)×\(size.pixels)px)")
    } catch {
        fputs("  ✗ Failed: \(size.filename) — \(error)\n", stderr)
        exit(1)
    }
    jsonImages.append("""
        {
          "filename" : "\(size.filename)",
          "idiom" : "mac",
          "scale" : "\(size.scale)x",
          "size" : "\(size.points)x\(size.points)"
        }
        """)
}

// Update Contents.json with filenames so Xcode generates the .icns
let contentsJson = """
{
  "images" : [
\(jsonImages.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try contentsJson.write(
    toFile: (outputDir as NSString).appendingPathComponent("Contents.json"),
    atomically: true, encoding: .utf8
)
print("  ✓ Contents.json updated")
print("Done. Icon assets written to \(outputDir)")

#!/usr/bin/env swift
/// generate-icon.swift — Generates AppIcon PNG assets for all required macOS sizes.
///
/// Usage: swift generate-icon.swift <output-dir>
/// The output directory should be SHH/Assets.xcassets/AppIcon.appiconset/
///
/// Renders the exact same orange squircle + waveform icon as AppDelegate.makeAppIcon().
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

    // Waveform SF Symbol rasterised onto a scratch NSBitmapImageRep
    let fgColor = NSColor(red: 246/255.0, green: 247/255.0, blue: 235/255.0, alpha: 1.0)
    let symConfig = NSImage.SymbolConfiguration(paletteColors: [fgColor])
    if let symImg = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
        .withSymbolConfiguration(symConfig) {

        let targetH = iconRect.height * 0.50
        let symScale = targetH / symImg.size.height
        let symW = symImg.size.width * symScale
        let symRect = CGRect(
            x: iconRect.midX - symW / 2,
            y: iconRect.midY - targetH / 2,
            width: symW, height: targetH
        )

        // Render the symbol into an offscreen bitmap, then composite into our CGContext
        let symPixW = Int(ceil(symW))
        let symPixH = Int(ceil(targetH))
        if let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: symPixW, pixelsHigh: symPixH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            symImg.draw(in: NSRect(x: 0, y: 0, width: symW, height: targetH),
                        from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()

            if let symCGImage = bitmapRep.cgImage {
                ctx.draw(symCGImage, in: symRect)
            }
        }
    }

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

#!/usr/bin/env swift
// Generates the React Native app's icon set in mobile/assets — the same design as the native iOS icon
// (scripts/generate_app_icon.swift): SF Symbol figure.strengthtraining.traditional, black, on royal blue.
//
//   icon.png                     1024, opaque, full-bleed (iOS applies its own corner mask)
//   android-icon-foreground.png  1024, transparent; figure kept inside Android's adaptive-icon safe zone
//   android-icon-background.png  1024, solid royal blue
//   android-icon-monochrome.png  1024, transparent; figure only (Android themed icons tint it)
//
// Usage (from repo root):  swift scripts/generate_mobile_icons.swift mobile/assets
import AppKit

guard let outDir = CommandLine.arguments.dropFirst().first else {
    FileHandle.standardError.write(Data("Usage: swift generate_mobile_icons.swift <output-directory>\n".utf8))
    exit(1)
}

let size = 1024
let s = CGFloat(size)
// CSS “Royal Blue” #4169E1.
let royalBlue = CGColor(red: 65 / 255, green: 105 / 255, blue: 225 / 255, alpha: 1)

/// - Parameters:
///   - background: fill colour, or nil for a transparent canvas.
///   - figureScale: symbol point size as a fraction of the canvas, or nil for no figure.
func render(_ name: String, background: CGColor?, figureScale: CGFloat?) throws {
    let opaque = background != nil
    let alphaInfo = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alphaInfo.rawValue
    ) else { fatalError("Could not create bitmap context") }

    if let background {
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    }

    if let figureScale {
        guard let symbol = NSImage(systemSymbolName: "figure.strengthtraining.traditional", accessibilityDescription: nil),
              let figure = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: s * figureScale, weight: .medium))
        else { fatalError("Missing SF Symbol") }
        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let sz = figure.size
        figure.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
        NSGraphicsContext.restoreGraphicsState()
    }

    guard let image = ctx.makeImage() else { fatalError("Could not make image") }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Could not create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
    print("Wrote \(url.path)")
}

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
// 0.52 matches the native icon. Android masks adaptive icons to the middle two-thirds, so the figure is smaller there.
try render("icon.png", background: royalBlue, figureScale: 0.52)
try render("android-icon-foreground.png", background: nil, figureScale: 0.36)
try render("android-icon-background.png", background: royalBlue, figureScale: nil)
try render("android-icon-monochrome.png", background: nil, figureScale: 0.36)

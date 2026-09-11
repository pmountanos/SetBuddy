#!/usr/bin/env swift
// Generates 1024×1024 PNG for AppIcon (SF Symbol figure.strengthtraining.traditional on royal blue background).
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard let outDir = args.first else {
    FileHandle.standardError.write(Data("Usage: swift generate_app_icon.swift <output-directory>\n".utf8))
    exit(1)
}

let pixelWidth = 1024
let pixelHeight = 1024
let s = CGFloat(pixelWidth)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: pixelWidth * 4,
    bitsPerPixel: 32
) else {
    fatalError("Could not create bitmap")
}

guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Could not create graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gctx
defer { NSGraphicsContext.restoreGraphicsState() }

// CSS “Royal Blue” #4169E1 — strong contrast with template SF Symbol rendering.
NSColor(red: 65 / 255, green: 105 / 255, blue: 225 / 255, alpha: 1).setFill()
let corner = s * 0.2237
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: corner, yRadius: corner).fill()

guard let symbol = NSImage(systemSymbolName: "figure.strengthtraining.traditional", accessibilityDescription: nil) else {
    fatalError("Missing SF Symbol")
}
let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.52, weight: .medium)
let rendered = symbol.withSymbolConfiguration(cfg)!
let sz = rendered.size
let rect = NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height)
rendered.draw(in: rect)

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let pathOut = (outDir as NSString).appendingPathComponent("AppIcon-1024.png")
try png.write(to: URL(fileURLWithPath: pathOut))
print("Wrote \(pathOut)")

#!/usr/bin/env swift
//
// Renders the application icon without Xcode, then converts it to .icns.
// Usage: swift Scripts/make-icon.swift Resources/AppIcon.icns
//
import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = outputURL.deletingLastPathComponent()
    .appendingPathComponent("AppIcon.iconset", isDirectory: true)

let fileManager = FileManager.default
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

/// Draws the icon artwork into the current graphics context, in a 0...1 space.
func drawIcon(in size: CGFloat) {
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)

    // Background squircle.
    let inset = size * 0.015
    let plate = bounds.insetBy(dx: inset, dy: inset)
    let radius = size * 0.225
    let platePath = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.16, green: 0.22, blue: 0.72, alpha: 1.0),
        NSColor(srgbRed: 0.33, green: 0.38, blue: 0.98, alpha: 1.0)
    ])
    gradient?.draw(in: platePath, angle: -65)

    // Soft top light falloff for depth (no hard edges).
    NSGraphicsContext.saveGraphicsState()
    platePath.addClip()
    let sheen = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.16),
        NSColor.white.withAlphaComponent(0.0)
    ])
    sheen?.draw(in: NSRect(x: 0, y: size * 0.35, width: size, height: size * 0.65), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Two layered "profile containers": back card outlined, front card solid.
    let backRect = NSRect(x: size * 0.20, y: size * 0.42,
                          width: size * 0.44, height: size * 0.40)
    let back = NSBezierPath(roundedRect: backRect,
                            xRadius: size * 0.075, yRadius: size * 0.075)
    back.lineWidth = max(size * 0.035, 1.0)
    NSColor.white.withAlphaComponent(0.55).setStroke()
    back.stroke()

    let frontRect = NSRect(x: size * 0.34, y: size * 0.18,
                           width: size * 0.46, height: size * 0.42)
    let front = NSBezierPath(roundedRect: frontRect,
                             xRadius: size * 0.075, yRadius: size * 0.075)
    NSColor.white.withAlphaComponent(0.20).setFill()
    front.fill()
    front.lineWidth = max(size * 0.045, 1.0)
    NSColor.white.setStroke()
    front.stroke()

    // Three dots inside the front card: hint of "separate identities".
    let dotRadius = size * 0.028
    let dotY = frontRect.midY
    let startX = frontRect.minX + size * 0.085
    let spacing = size * 0.085
    for index in 0..<3 {
        let dot = NSBezierPath(ovalIn: NSRect(
            x: startX + CGFloat(index) * spacing - dotRadius,
            y: dotY - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
        NSColor.white.withAlphaComponent(index == 0 ? 0.95 : 0.55).setFill()
        dot.fill()
    }
}

func pngData(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
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
    ) else { return nil }

    rep.size = NSSize(width: pixelSize, height: pixelSize)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill(using: .copy)
    drawIcon(in: CGFloat(pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

struct Variant {
    let name: String
    let pixels: Int
}

let variants: [Variant] = [
    Variant(name: "icon_16x16.png", pixels: 16),
    Variant(name: "icon_16x16@2x.png", pixels: 32),
    Variant(name: "icon_32x32.png", pixels: 32),
    Variant(name: "icon_32x32@2x.png", pixels: 64),
    Variant(name: "icon_128x128.png", pixels: 128),
    Variant(name: "icon_128x128@2x.png", pixels: 256),
    Variant(name: "icon_256x256.png", pixels: 256),
    Variant(name: "icon_256x256@2x.png", pixels: 512),
    Variant(name: "icon_512x512.png", pixels: 512),
    Variant(name: "icon_512x512@2x.png", pixels: 1024)
]

for variant in variants {
    guard let data = pngData(pixelSize: variant.pixels) else {
        FileHandle.standardError.write(Data("failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    try data.write(to: iconsetURL.appendingPathComponent(variant.name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

try? fileManager.removeItem(at: iconsetURL)
print("wrote \(outputURL.path)")

#!/usr/bin/env swift

import AppKit
import Foundation

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iconsetURL = projectRoot.appending(path: "App/Ribbit.iconset")
let icnsURL = projectRoot.appending(path: "App/Ribbit.icns")

let pose = [
    "..gg.gg..",
    ".ggggggg.",
    ".g#ggg#g.",
    "ggggggggg",
    "gggmmmggg",
    ".ggwwwgg.",
    "ggggggggg",
    "gg.....gg",
]

let representations = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
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
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context

    let size = CGFloat(pixelSize)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    context.shouldAntialias = true
    let inset = max(1, floor(size * 0.035))
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = floor(size * 0.215)
    NSColor(srgbRed: 0.047, green: 0.055, blue: 0.071, alpha: 1).setFill()
    NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).fill()

    if pixelSize >= 32 {
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let edge = NSBezierPath(roundedRect: tile.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        edge.lineWidth = max(1, size / 512)
        edge.stroke()
    }

    context.shouldAntialias = false
    let pixel = max(1, floor(size * 0.072))
    let spriteWidth = CGFloat(pose[0].count) * pixel
    let spriteHeight = CGFloat(pose.count) * pixel
    let origin = CGPoint(x: floor((size - spriteWidth) / 2), y: floor((size - spriteHeight) / 2))

    for (row, line) in pose.enumerated() {
        for (column, value) in line.enumerated() where value != "." {
            let color: NSColor
            switch value {
            case "#", "m": color = NSColor(srgbRed: 0.047, green: 0.055, blue: 0.071, alpha: 1)
            case "w": color = NSColor(srgbRed: 0.82, green: 0.96, blue: 0.86, alpha: 1)
            default: color = NSColor(srgbRed: 0.20, green: 0.92, blue: 0.47, alpha: 1)
            }
            color.setFill()
            NSRect(
                x: origin.x + CGFloat(column) * pixel,
                y: origin.y + CGFloat(pose.count - row - 1) * pixel,
                width: pixel,
                height: pixel
            ).fill()
        }
    }

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

for (filename, pixelSize) in representations {
    try renderIcon(pixelSize: pixelSize).write(to: iconsetURL.appending(path: filename), options: .atomic)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("Generated \(icnsURL.path)")

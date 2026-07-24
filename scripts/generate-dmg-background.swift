#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-dmg-background.swift <output.png>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 660, height: 420)
let scale = 2
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width) * scale,
    pixelsHigh: Int(size.height) * scale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("unable to create DMG background bitmap\n", stderr)
    exit(1)
}

bitmap.size = size
NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("unable to create DMG background context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context

let canvas = NSRect(origin: .zero, size: size)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.035, green: 0.090, blue: 0.078, alpha: 1),
    NSColor(calibratedRed: 0.055, green: 0.145, blue: 0.116, alpha: 1),
])!
gradient.draw(in: canvas, angle: -18)

// Soft lily-pad shapes keep the background recognizably Ribbit without
// competing with Finder's draggable icons.
for (rect, alpha) in [
    (NSRect(x: -85, y: -95, width: 310, height: 250), 0.11),
    (NSRect(x: 505, y: 275, width: 225, height: 180), 0.08),
    (NSRect(x: 430, y: -135, width: 340, height: 270), 0.06),
] {
    NSColor(calibratedRed: 0.36, green: 0.95, blue: 0.61, alpha: alpha).setFill()
    NSBezierPath(ovalIn: rect).fill()
}

// Finder owns the item-label color and renders it black in light appearance.
// Pale plates keep both draggable item names readable over the dark artwork.
for rect in [
    NSRect(x: 126, y: 101, width: 108, height: 29),
    NSRect(x: 414, y: 101, width: 132, height: 29),
] {
    NSColor(calibratedRed: 0.82, green: 0.98, blue: 0.87, alpha: 0.92).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 14.5, yRadius: 14.5).fill()
}

let centered = NSMutableParagraphStyle()
centered.alignment = .center

("RIBBIT" as NSString).draw(
    in: NSRect(x: 0, y: 334, width: size.width, height: 42),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 31, weight: .black),
        .foregroundColor: NSColor(calibratedRed: 0.62, green: 1.0, blue: 0.73, alpha: 1),
        .kern: 5.2,
        .paragraphStyle: centered,
    ]
)

("Your terminal workspace, ready to leap." as NSString).draw(
    in: NSRect(x: 0, y: 302, width: size.width, height: 25),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.72),
        .paragraphStyle: centered,
    ]
)

let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 270, y: 190))
arrow.line(to: NSPoint(x: 386, y: 190))
arrow.move(to: NSPoint(x: 372, y: 203))
arrow.line(to: NSPoint(x: 386, y: 190))
arrow.line(to: NSPoint(x: 372, y: 177))
NSColor(calibratedRed: 0.59, green: 0.98, blue: 0.70, alpha: 0.8).setStroke()
arrow.stroke()

("DRAG TO INSTALL" as NSString).draw(
    in: NSRect(x: 250, y: 146, width: 156, height: 18),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.48),
        .kern: 1.6,
        .paragraphStyle: centered,
    ]
)

("Requires macOS 14 or later" as NSString).draw(
    in: NSRect(x: 0, y: 30, width: size.width, height: 18),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.42),
        .paragraphStyle: centered,
    ]
)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode DMG background\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL)
} catch {
    fputs("unable to write DMG background: \(error)\n", stderr)
    exit(1)
}

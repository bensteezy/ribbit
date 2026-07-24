import AppKit
import SwiftUI

@MainActor
enum FrogPixelArt {
    static let restingPose = [
        "..gg.gg..",
        ".ggggggg.",
        ".g#ggg#g.",
        "ggggggggg",
        "gggmmmggg",
        ".ggwwwgg.",
        "ggggggggg",
        "gg.....gg",
    ]

    static let workingPoses = [
        restingPose,
        [
            "..gg.gg..",
            ".ggggggg.",
            ".g#ggg#g.",
            "ggggggggg",
            "gggmmmggg",
            ".ggwwwgg.",
            ".ggggggg.",
            "gg.....gg",
        ],
        [
            "..gg.gg..",
            ".ggggggg.",
            ".ggggggg.",
            "ggggggggg",
            "gggmmmggg",
            ".ggwwwgg.",
            "ggggggggg",
            ".gg...gg.",
        ],
    ]

    static func workingPoseIndex(at date: Date) -> Int {
        let tick = Int(date.timeIntervalSinceReferenceDate * 4)
        return abs(tick) % workingPoses.count
    }

    static let menuIcon: NSImage = {
        let pixelSize: CGFloat = 2
        let image = NSImage(
            size: NSSize(width: 9 * pixelSize, height: 8 * pixelSize),
            flipped: true
        ) { _ in
            for (row, line) in restingPose.enumerated() {
                for (column, value) in line.enumerated() where value != "." {
                    let color: NSColor
                    switch value {
                    case "#", "m": continue
                    case "w": color = NSColor(srgbRed: 0.82, green: 0.96, blue: 0.86, alpha: 1)
                    default: color = RibbitTheme.nsAccent
                    }
                    color.setFill()
                    NSRect(
                        x: CGFloat(column) * pixelSize,
                        y: CGFloat(row) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    ).fill()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }()
}

struct FrogMascotView: View {
    var pixelSize: CGFloat = 3

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            for (row, line) in FrogPixelArt.restingPose.enumerated() {
                for (column, value) in line.enumerated() where value != "." {
                    let color: Color
                    switch value {
                    case "#", "m": color = RibbitTheme.canvas
                    case "w": color = Color(nsColor: NSColor(srgbRed: 0.82, green: 0.96, blue: 0.86, alpha: 1))
                    default: color = RibbitTheme.accent
                    }
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * pixelSize,
                            y: CGFloat(row) * pixelSize,
                            width: pixelSize,
                            height: pixelSize
                        )),
                        with: .color(color)
                    )
                }
            }
        }
        .frame(width: 9 * pixelSize, height: 8 * pixelSize)
        .accessibilityLabel("ribbit frog")
    }
}

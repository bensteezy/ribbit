import AppKit

struct RibbitNotchScreenMetrics: Equatable, Sendable {
    var frame: CGRect
    var visibleFrame: CGRect
    var safeAreaTop: CGFloat
    var auxiliaryTopLeftArea: CGRect?
    var auxiliaryTopRightArea: CGRect?
    var backingScaleFactor: CGFloat

    @MainActor
    init(screen: NSScreen) {
        frame = screen.frame
        visibleFrame = screen.visibleFrame
        safeAreaTop = screen.safeAreaInsets.top
        auxiliaryTopLeftArea = screen.auxiliaryTopLeftArea
        auxiliaryTopRightArea = screen.auxiliaryTopRightArea
        backingScaleFactor = screen.backingScaleFactor
    }

    init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?,
        backingScaleFactor: CGFloat
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.backingScaleFactor = backingScaleFactor
    }
}

enum RibbitAgentNotchGeometry {
    static let compactWingWidth: CGFloat = 28
    static let compactTopCornerRadius: CGFloat = 6
    static let expandedTopCornerRadius: CGFloat = 19
    static let compactSurfaceCornerRadius: CGFloat = 14
    static let expandedSurfaceCornerRadius: CGFloat = 24
    static let expandedWidth: CGFloat = 612
    static let rowHeight: CGFloat = 54
    static let attentionDetailHeight: CGFloat = 142
    static let fallbackCompactSize = CGSize(width: 112, height: 30)

    static func hasPhysicalNotch(_ metrics: RibbitNotchScreenMetrics) -> Bool {
        metrics.safeAreaTop > 0
            && metrics.auxiliaryTopLeftArea != nil
            && metrics.auxiliaryTopRightArea != nil
    }

    static func hardwareNotchWidth(
        _ metrics: RibbitNotchScreenMetrics
    ) -> CGFloat {
        guard let left = metrics.auxiliaryTopLeftArea,
              let right = metrics.auxiliaryTopRightArea else { return 0 }
        return max(0, right.minX - left.maxX)
    }

    static func compactSize(
        for metrics: RibbitNotchScreenMetrics
    ) -> CGSize {
        guard hasPhysicalNotch(metrics) else { return fallbackCompactSize }
        return CGSize(
            width: hardwareNotchWidth(metrics)
                + (compactWingWidth + compactTopCornerRadius) * 2,
            height: metrics.safeAreaTop
        )
    }

    static func expandedSize(
        for metrics: RibbitNotchScreenMetrics,
        displayedSessionCount: Int,
        showsAttentionDetail: Bool
    ) -> CGSize {
        let physical = hasPhysicalNotch(metrics)
        let headerHeight = physical ? metrics.safeAreaTop : fallbackCompactSize.height
        let rowCount = min(max(displayedSessionCount, 1), 5)
        let bodyHeight = CGFloat(rowCount) * rowHeight
            + (showsAttentionDetail ? attentionDetailHeight : 0)
            + 8
        let minimumWidth = physical ? hardwareNotchWidth(metrics) + 150 : 0
        return CGSize(
            width: min(
                max(expandedWidth, minimumWidth) + expandedTopCornerRadius * 2,
                max(320, metrics.frame.width - 32)
            ),
            height: headerHeight + bodyHeight
        )
    }

    static func surfaceCornerRadius(for height: CGFloat) -> CGFloat {
        interpolatedCornerRadius(
            for: height,
            compact: compactSurfaceCornerRadius,
            expanded: expandedSurfaceCornerRadius
        )
    }

    static func topCornerRadius(for height: CGFloat) -> CGFloat {
        interpolatedCornerRadius(
            for: height,
            compact: compactTopCornerRadius,
            expanded: expandedTopCornerRadius
        )
    }

    private static func interpolatedCornerRadius(
        for height: CGFloat,
        compact: CGFloat,
        expanded: CGFloat
    ) -> CGFloat {
        let compactHeight = fallbackCompactSize.height
        let expandedHeight = compactHeight + rowHeight * 2
        let progress = min(
            max((height - compactHeight) / (expandedHeight - compactHeight), 0),
            1
        )
        return compact + (expanded - compact) * progress
    }

    static func topAnchoredFrame(
        size: CGSize,
        on metrics: RibbitNotchScreenMetrics
    ) -> CGRect {
        let scale = max(1, metrics.backingScaleFactor)
        let width = rounded(size.width, scale: scale)
        let height = rounded(size.height, scale: scale)
        let x = rounded(metrics.frame.midX - width / 2, scale: scale)
        let top = hasPhysicalNotch(metrics)
            ? rounded(metrics.frame.maxY, scale: scale)
            : rounded(metrics.visibleFrame.maxY - 4, scale: scale)
        return CGRect(
            x: x,
            y: top - height,
            width: width,
            height: height
        )
    }

    private static func rounded(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}

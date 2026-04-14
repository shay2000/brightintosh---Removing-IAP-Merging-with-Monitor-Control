//
//  UnifiedBrightnessSlider.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 13.04.26.
//
//  MonitorControl-style slider that covers both normal system brightness
//  (0%–100%) and BrightIntosh's XDR extended range (100%–~159%).
//
//  Visual anatomy:
//
//      0% ───────────── 100% ━━━━━━━━━━━━ maxExtra
//      [neutral fill  ][tick][   XDR fill (amber)   ]
//
//  Tick is drawn at `1.0`. Below 1.0 the filled portion uses the normal
//  bar fill color; above 1.0 it uses `StyledSliderXDRBarColor` (amber).
//  A small snap region around 1.0 lets the user land exactly on 100%
//  when they drag across the boundary.
//

import Cocoa

/// Custom slider cell that draws a tick at the 100% mark and switches the
/// filled-bar color above that mark.
final class UnifiedBrightnessSliderCell: StyledSliderCell {

    /// Slider value at which the XDR tick is drawn (always 1.0).
    private let xdrBoundary: Double = 1.0

    /// How close (in normalized slider units) the user has to drag to snap.
    /// 0.02 ≈ 2% of the full range.
    private let snapEpsilon: Double = 0.02

    /// Color of the filled bar above the 100% tick.
    private var xdrFillColor: NSColor {
        return NSColor(named: NSColor.Name("StyledSliderXDRBarColor"))
            ?? NSColor.systemOrange
    }

    override func drawBar(inside barOuterRect: NSRect, flipped: Bool) {
        let normalizedValue = getNormalizedSliderValue()
        let knobDiameter = barOuterRect.height
        let radius = knobDiameter * 0.5
        let knobStart = barOuterRect.origin.x
            + (barOuterRect.width - knobDiameter) * normalizedValue

        // Bar background
        let bar = NSBezierPath(roundedRect: barOuterRect, xRadius: radius, yRadius: radius)
        barFillColor.setFill()
        bar.fill()

        // Boundary x position (where 100% sits).
        let boundaryNormalized = normalizedBoundary()
        let boundaryX = barOuterRect.origin.x
            + (barOuterRect.width - knobDiameter) * boundaryNormalized
            + knobDiameter * 0.5

        // Filled portion, split at the boundary.
        let barFilledWidth = knobStart + knobDiameter
        let filledEndX = barOuterRect.origin.x + barFilledWidth

        // SDR portion: from bar start to min(boundary, filledEnd)
        let sdrEnd = min(boundaryX, filledEndX)
        if sdrEnd > barOuterRect.origin.x {
            let sdrRect = NSRect(
                x: barOuterRect.origin.x,
                y: barOuterRect.origin.y,
                width: sdrEnd - barOuterRect.origin.x,
                height: barOuterRect.height)
            let sdrPath = NSBezierPath(roundedRect: sdrRect, xRadius: radius, yRadius: radius)
            barFilledFillColor.setFill()
            sdrPath.fill()
        }

        // XDR portion: from boundary to filledEnd (if we're above 100%)
        if filledEndX > boundaryX {
            let xdrRect = NSRect(
                x: boundaryX,
                y: barOuterRect.origin.y,
                width: filledEndX - boundaryX,
                height: barOuterRect.height)
            // Clip to the rounded bar so the amber doesn't spill past the rounded end.
            NSGraphicsContext.saveGraphicsState()
            bar.setClip()
            xdrFillColor.setFill()
            NSBezierPath(rect: xdrRect).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Draw the boundary tick on top.
        let tickRect = NSRect(
            x: boundaryX - 1.0,
            y: barOuterRect.origin.y - 2.0,
            width: 2.0,
            height: barOuterRect.height + 4.0)
        barFillColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(rect: tickRect).fill()
    }

    override func continueTracking(last lastPoint: NSPoint,
                                   current currentPoint: NSPoint,
                                   in controlView: NSView) -> Bool {
        let result = super.continueTracking(last: lastPoint, current: currentPoint, in: controlView)

        // Snap to exactly 100% when the user's cursor is within the snap band.
        let normalized = getNormalizedSliderValue()
        let boundary = normalizedBoundary()
        if abs(normalized - boundary) < snapEpsilon && self.doubleValue != xdrBoundary {
            self.doubleValue = xdrBoundary
            controlView.needsDisplay = true
        }
        return result
    }

    /// Normalized position of the 100% boundary within the slider's range.
    private func normalizedBoundary() -> Double {
        guard maxValue > minValue else { return 0.5 }
        return (xdrBoundary - minValue) / (maxValue - minValue)
    }
}

/// Slider subclass that uses `UnifiedBrightnessSliderCell` and is
/// pre-configured for the unified `[0.0, deviceMax]` range.
final class UnifiedBrightnessSlider: NSSlider {

    convenience init(value: Double,
                     target: AnyObject?,
                     action: Selector?) {
        self.init(frame: .zero)
        let deviceMax = Double(getDeviceMaxBrightness())
        self.minValue = 0.0
        self.maxValue = deviceMax
        self.doubleValue = max(0.0, min(deviceMax, value))
        self.target = target
        self.action = action
        self.isContinuous = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.cell = UnifiedBrightnessSliderCell()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.cell = UnifiedBrightnessSliderCell()
    }
}

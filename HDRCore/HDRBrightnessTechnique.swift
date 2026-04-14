//
//  HDRBrightnessTechnique.swift
//  HDRCore (isolated from BrightIntosh)
//
//  Extracted from BrightIntosh's `BrightnessTechnique.swift`. This file
//  contains:
//    - `GammaTable`        : snapshot + multiply-and-apply of the display gamma LUT
//    - `HDRGammaTechnique` : per-display orchestration of the overlay window
//                            and gamma multiplier
//
//  No BrightIntosh-specific settings/auth/UI dependencies remain. The
//  per-display brightness factor is supplied by the caller via
//  `HDRBrightnessController`.
//

import Cocoa
import Foundation

/// Snapshot + multiplier helper for a display's gamma LUT.
public final class GammaTable {

    public static let tableSize: UInt32 = 256

    public var redTable:   [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    public var greenTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    public var blueTable:  [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))

    private init() {}

    /// Captures the current gamma LUT of `displayId` into a new `GammaTable`.
    /// Returns `nil` if the read fails.
    public static func createFromCurrentGammaTable(displayId: CGDirectDisplayID) -> GammaTable? {
        let table = GammaTable()
        var sampleCount: UInt32 = 0
        let result = CGGetDisplayTransferByTable(
            displayId,
            tableSize,
            &table.redTable,
            &table.greenTable,
            &table.blueTable,
            &sampleCount
        )
        guard result == CGError.success else { return nil }
        return table
    }

    /// Multiplies the stored LUT by `factor` and installs the result as
    /// the display's gamma curve. Pass `factor = 1.0` to restore the
    /// original LUT.
    public func setTableForScreen(displayId: CGDirectDisplayID, factor: Float = 1.0) {
        var newRed   = redTable.map   { $0 * factor }
        var newGreen = greenTable.map { $0 * factor }
        var newBlue  = blueTable.map  { $0 * factor }
        CGSetDisplayTransferByTable(
            displayId,
            GammaTable.tableSize,
            &newRed,
            &newGreen,
            &newBlue
        )
    }
}

/// Abstract base kept for parity with BrightIntosh's original class hierarchy.
/// `HDRGammaTechnique` is the one concrete implementation.
@MainActor
public class HDRBrightnessTechnique {
    public fileprivate(set) var isEnabled: Bool = false

    public init() {}

    public func enable() { fatalError("Subclasses must implement enable()") }
    public func enableScreen(screen: NSScreen) { fatalError("Subclasses must implement enableScreen()") }
    public func disable() { fatalError("Subclasses must implement disable()") }
    public func adjustBrightness() {}
    public func screenUpdate(screens: [NSScreen]) {}
}

/// Per-display orchestration: opens an overlay window on every XDR screen,
/// snapshots its gamma LUT, and re-multiplies the LUT whenever the
/// brightness factor changes.
@MainActor
public final class HDRGammaTechnique: HDRBrightnessTechnique {

    private var overlayWindowControllers: [CGDirectDisplayID: HDROverlayWindowController] = [:]
    private var gammaTables: [CGDirectDisplayID: GammaTable] = [:]

    /// Current multiplicative factor applied to every gamma LUT.
    /// Clamped on write to `[1.0, hdrGetDeviceMaxBrightness()]`.
    public var brightnessFactor: Float = 1.0 {
        didSet {
            brightnessFactor = max(1.0, min(hdrGetDeviceMaxBrightness(), brightnessFactor))
        }
    }

    /// When `true`, external XDR displays are excluded from enabling.
    public var onlyOnBuiltIn: Bool = false

    public override init() { super.init() }

    public override func enable() {
        hdrGetXDRDisplays(onlyBuiltIn: onlyOnBuiltIn).forEach { screen in
            enableScreen(screen: screen)
        }
        isEnabled = true
        adjustBrightness()
    }

    public override func enableScreen(screen: NSScreen) {
        guard let displayId = screen.hdrDisplayId else { return }

        if gammaTables[displayId] == nil {
            gammaTables[displayId] = GammaTable.createFromCurrentGammaTable(displayId: displayId)
        }

        let controller = HDROverlayWindowController(screen: screen)
        overlayWindowControllers[displayId] = controller

        let rect = NSRect(x: screen.frame.origin.x,
                          y: screen.frame.origin.y,
                          width: 1, height: 1)
        controller.open(rect: rect)
    }

    public override func disable() {
        isEnabled = false
        overlayWindowControllers.values.forEach { $0.window?.close() }
        overlayWindowControllers.removeAll()
        gammaTables.removeAll()
        resetGammaTable()
    }

    public override func adjustBrightness() {
        super.adjustBrightness()
        guard isEnabled else { return }
        let gamma = brightnessFactor
        for controller in overlayWindowControllers.values {
            if let displayId = controller.screen.hdrDisplayId,
               let gammaTable = gammaTables[displayId] {
                gammaTable.setTableForScreen(displayId: displayId, factor: gamma)
            }
        }
    }

    private func resetGammaTable() {
        CGDisplayRestoreColorSyncSettings()
    }

    public override func screenUpdate(screens: [NSScreen]) {
        let allDisplayIds = screens.compactMap { $0.hdrDisplayId }
        let toBeDeactivated = overlayWindowControllers.keys.filter { !allDisplayIds.contains($0) }

        for displayId in toBeDeactivated {
            overlayWindowControllers[displayId]?.window?.close()
            // Restore the original LUT on screens that are disappearing.
            gammaTables[displayId]?.setTableForScreen(displayId: displayId, factor: 1.0)
            gammaTables.removeValue(forKey: displayId)
            overlayWindowControllers.removeValue(forKey: displayId)
        }

        for screen in screens {
            guard let displayId = screen.hdrDisplayId else { continue }
            if overlayWindowControllers.keys.contains(displayId) {
                overlayWindowControllers[displayId]?.reposition(screen: screen)
            } else {
                enableScreen(screen: screen)
            }
        }

        adjustBrightness()
    }
}

//
//  HDROverlayWindow.swift
//  HDRCore (isolated from BrightIntosh)
//
//  Extracted from BrightIntosh's `OverlayWindow.swift`. This is the
//  transparent 1×1 px NSWindow that hosts the `HDRMetalOverlay` MTKView
//  on each XDR screen.
//
//  Without this window present on screen, macOS will not keep the
//  display in extended-dynamic-range mode.
//

import Cocoa
import OSLog

private let hdrOverlayLogger = Logger(
    subsystem: "HDRCore.OverlayWindow",
    category: "Core"
)

/// A tiny transparent NSWindow that lives at the corner of an XDR screen
/// and hosts the Metal EDR overlay.
public final class HDROverlayWindow: NSWindow {

    public var overlay: HDRMetalOverlay?
    public let fullsize: Bool

    public init(fullsize: Bool = false) {
        self.fullsize = fullsize
        let rect = NSRect(x: 0, y: 0, width: 1, height: 1)

        if fullsize {
            super.init(contentRect: rect,
                       styleMask: [.fullSizeContentView, .borderless],
                       backing: .buffered,
                       defer: false)
            if #available(macOS 13.0, *) {
                collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle,
                                      .canJoinAllApplications, .fullScreenAuxiliary]
            } else {
                collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle,
                                      .fullScreenAuxiliary]
            }
            level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        } else {
            super.init(contentRect: rect,
                       styleMask: [],
                       backing: BackingStoreType(rawValue: 0)!,
                       defer: false)
            collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
            level = .screenSaver
            canHide = false
            isMovableByWindowBackground = true
            isReleasedWhenClosed = false
            alphaValue = 1
        }

        isOpaque = false
        hasShadow = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    public func addMetalOverlay(screen: NSScreen) {
        overlay = HDRMetalOverlay(frame: frame, multiplyCompositing: self.fullsize)
        overlay?.screenUpdate(screen: screen)
        overlay?.autoresizingMask = [.width, .height]
        contentView = overlay
    }

    public func screenUpdate(screen: NSScreen) {
        overlay?.screenUpdate(screen: screen)
    }
}

/// Window controller that pins an `HDROverlayWindow` to a given `NSScreen`
/// and keeps it anchored as the display geometry changes.
public final class HDROverlayWindowController: NSWindowController, NSWindowDelegate {

    public let fullsize: Bool
    public let screen: NSScreen

    public init(screen: NSScreen, fullsize: Bool = false) {
        self.screen = screen
        self.fullsize = fullsize
        let overlayWindow = HDROverlayWindow(fullsize: fullsize)

        super.init(window: overlayWindow)
        overlayWindow.delegate = self
    }

    public func open(rect: NSRect) {
        guard let window = self.window as? HDROverlayWindow else { return }
        window.setFrame(rect, display: true)

        if !fullsize {
            reposition(screen: screen)
        }

        window.orderFrontRegardless()
        window.addMetalOverlay(screen: screen)
    }

    public func reposition(screen: NSScreen) {
        let targetPosition = getIdealPosition(screen: screen)
        window?.setFrameOrigin(targetPosition)
    }

    public func getIdealPosition(screen: NSScreen) -> CGPoint {
        var position = screen.frame.origin
        position.y += screen.frame.height - 1
        return position
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func windowDidMove(_ notification: Notification) {
        if let window = window, let screen = window.screen {
            hdrOverlayLogger.info(
                "Window moved to (\(window.frame.origin.x), \(window.frame.origin.y)), current screen: \(screen.localizedName), expected: \(self.screen.localizedName)"
            )
            if window.frame.origin != getIdealPosition(screen: self.screen) {
                reposition(screen: self.screen)
            }
        }
    }
}

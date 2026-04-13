//
//  HDRBrightnessController.swift
//  HDRCore (isolated from BrightIntosh)
//
//  Singleton high-level controller that an integrator talks to. Replaces
//  BrightIntosh's `BrightnessManager.swift`, but without Combine, without
//  `Authorizer`, without `BrightIntoshSettings`, and without the trial
//  subsystem.
//
//  Typical use:
//
//      HDRBrightnessController.shared.setBrightness(1.5)
//      HDRBrightnessController.shared.enable()
//      ...
//      HDRBrightnessController.shared.disable()
//
//  The integrator must forward these two notifications:
//
//      - NSApplication.didChangeScreenParametersNotification
//            -> handleScreenParametersChanged()
//      - NSWorkspace.screensDidWakeNotification
//            -> handleScreensDidWake()
//

import Cocoa

@MainActor
public final class HDRBrightnessController {

    public static let shared = HDRBrightnessController()

    private let technique = HDRGammaTechnique()

    /// All currently attached screens (not just XDR ones) — retained so
    /// we can detect changes across notifications.
    private var screens: [NSScreen] = NSScreen.screens
    private var xdrScreens: [NSScreen] = []

    private init() {
        self.xdrScreens = hdrGetXDRDisplays(onlyBuiltIn: technique.onlyOnBuiltIn)
    }

    // MARK: - Public API

    /// `true` if the HDR brightening mechanism is currently active.
    public var isEnabled: Bool { technique.isEnabled }

    /// Current gamma multiplier in `[1.0, hdrGetDeviceMaxBrightness()]`.
    public var brightness: Float {
        get { technique.brightnessFactor }
        set {
            technique.brightnessFactor = newValue
            technique.adjustBrightness()
        }
    }

    /// When `true`, external XDR displays are excluded.
    public var onlyOnBuiltIn: Bool {
        get { technique.onlyOnBuiltIn }
        set {
            technique.onlyOnBuiltIn = newValue
            handleScreenParametersChanged()
        }
    }

    /// Set the gamma multiplier. Values outside the supported range are
    /// clamped. No-op on screens currently not in the XDR set.
    public func setBrightness(_ factor: Float) {
        self.brightness = factor
    }

    /// Activates the HDR overlay + gamma multiplier on every XDR screen.
    public func enable() {
        guard !technique.isEnabled else { return }
        // Ensure brightness is in-range for this device.
        technique.brightnessFactor = max(1.0, min(hdrGetDeviceMaxBrightness(), technique.brightnessFactor))
        technique.enable()
    }

    /// Tears down every overlay and restores the original gamma LUT.
    public func disable() {
        guard technique.isEnabled else { return }
        technique.disable()
    }

    // MARK: - System event hooks

    /// Call from `NSApplication.didChangeScreenParametersNotification`.
    public func handleScreenParametersChanged() {
        let newScreens = NSScreen.screens
        let newXdrDisplays = hdrGetXDRDisplays(onlyBuiltIn: technique.onlyOnBuiltIn)

        var changed = newScreens.count != screens.count
            || newXdrDisplays.count != xdrScreens.count

        if !changed {
            for screen in screens {
                let same = newScreens.first { $0.hdrDisplayId == screen.hdrDisplayId }
                if same?.frame.origin != screen.frame.origin {
                    changed = true
                    break
                }
            }
        }

        if changed {
            screens = newScreens
            xdrScreens = newXdrDisplays
        }

        guard technique.isEnabled else { return }

        if !newScreens.isEmpty {
            if !technique.isEnabled {
                technique.enable()
            } else if changed {
                technique.screenUpdate(screens: xdrScreens)
            } else {
                technique.adjustBrightness()
            }
        } else {
            technique.disable()
        }
    }

    /// Call from `NSWorkspace.screensDidWakeNotification` —
    /// re-applies the gamma multiplier after macOS resets it at wake time.
    public func handleScreensDidWake() {
        if technique.isEnabled {
            technique.adjustBrightness()
        }
    }
}

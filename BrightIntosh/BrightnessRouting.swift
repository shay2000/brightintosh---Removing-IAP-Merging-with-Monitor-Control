//
//  BrightnessRouting.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 13.04.26.
//
//  Merges MonitorControl-style system brightness control with BrightIntosh's
//  XDR gamma boost behind a single unified slider range `[0.0, deviceMax]`.
//
//  Below 1.0, values drive the macOS internal-display backlight via the
//  (private) CoreDisplay `_Display_GetUserBrightness` / `_Display_SetUserBrightness`
//  functions — the same entry points MonitorControl uses for internal Apple
//  displays.
//
//  At or above 1.0, values drive the XDR gamma boost via
//  `HDRBrightnessController.shared`.
//
//  External non-Apple displays are not supported by this file; their
//  brightness remains under the user's manual control (DDC/i2c is a
//  deferred follow-up).
//

import Cocoa

// MARK: - System brightness control (CoreDisplay private API)

/// Minimal shim around `CoreDisplay_Display_SetUserBrightness` /
/// `CoreDisplay_Display_GetUserBrightness`. These are private macOS
/// symbols exposed by the `CoreDisplay.framework` bundle; we `dlopen`
/// and `dlsym` them at runtime so a symbol absence on a future macOS
/// release surfaces as `isAvailable == false` rather than a link error.
@MainActor
final class SystemBrightnessControl {

    static let shared = SystemBrightnessControl()

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID) -> Double
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Double) -> Void

    private let getBrightness: GetBrightnessFn?
    private let setBrightness: SetBrightnessFn?

    private init() {
        let framework = "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
        guard let handle = dlopen(framework, RTLD_NOW) else {
            self.getBrightness = nil
            self.setBrightness = nil
            return
        }
        // Note: we deliberately do not dlclose — the framework stays for the
        // process lifetime and closing it would invalidate the function ptrs.

        let getSym = dlsym(handle, "CoreDisplay_Display_GetUserBrightness")
        let setSym = dlsym(handle, "CoreDisplay_Display_SetUserBrightness")

        if let getSym = getSym {
            self.getBrightness = unsafeBitCast(getSym, to: GetBrightnessFn.self)
        } else {
            self.getBrightness = nil
        }
        if let setSym = setSym {
            self.setBrightness = unsafeBitCast(setSym, to: SetBrightnessFn.self)
        } else {
            self.setBrightness = nil
        }
    }

    /// `true` when both the get and set symbols resolved.
    var isAvailable: Bool {
        return getBrightness != nil && setBrightness != nil
    }

    /// The main display's `CGDirectDisplayID`, or `nil` if no main screen.
    private var mainDisplayId: CGDirectDisplayID? {
        return NSScreen.main?
            .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Reads the 0.0–1.0 backlight level of `displayId` or the main display.
    /// Returns `nil` if the private API is unavailable.
    func read(displayId: CGDirectDisplayID? = nil) -> Float? {
        guard let getBrightness = getBrightness else { return nil }
        guard let id = displayId ?? mainDisplayId else { return nil }
        return Float(getBrightness(id))
    }

    /// Writes a 0.0–1.0 backlight level to `displayId` or the main display.
    /// Values outside the range are clamped. No-op if the private API is
    /// unavailable, or if the target isn't the builtin display.
    func write(level: Float, displayId: CGDirectDisplayID? = nil) {
        guard let setBrightness = setBrightness else { return }
        guard let id = displayId ?? mainDisplayId else { return }
        let clamped = max(0.0, min(1.0, level))
        // Only touch the builtin display. External non-Apple displays would
        // require DDC/i2c, which is deferred.
        guard CGDisplayIsBuiltin(id) != 0 else {
            BrightnessRoutingWarnings.logExternalDisplayOnce()
            return
        }
        setBrightness(id, Double(clamped))
    }
}

/// One-shot logger so we don't spam the console if the user drags the
/// slider with an external non-Apple display focused.
@MainActor
private enum BrightnessRoutingWarnings {
    private static var externalDisplayWarned = false
    static func logExternalDisplayOnce() {
        guard !externalDisplayWarned else { return }
        externalDisplayWarned = true
        print("[BrightnessRouting] Below-100% brightness control for external non-Apple displays is not supported in this build.")
    }
}

// MARK: - Unified brightness routing

/// Where a unified brightness change originated. Determines whether the
/// first-time XDR warning is shown interactively or results in a
/// programmatic refusal.
enum BrightnessSource {
    case menuBar
    case settings
    case shortcut
    case cli
}

/// Outcome of routing a unified brightness value.
enum AppliedBrightness {
    /// The value was applied successfully.
    case applied
    /// The user cancelled the XDR first-use warning. Caller should reset
    /// the slider UI to `1.0`.
    case cancelled
    /// A non-GUI source (CLI) requested an XDR value but the user hasn't
    /// acknowledged the warning yet. Caller should surface an error.
    case requiresGUIAck
}

/// Applies a unified slider value `[0.0, 1.0 + (deviceMax - 1.0)]`:
///   - `value <= 1.0` → drives system backlight via `SystemBrightnessControl`.
///     Disables XDR if it was on.
///   - `value > 1.0`  → drives XDR via `HDRBrightnessController` /
///     `BrightIntoshSettings.shared.brightness`. On the *first* crossing
///     into the XDR zone from any GUI source, shows the XDR warning. From
///     the CLI, returns `.requiresGUIAck` instead.
@MainActor
@discardableResult
func applyUnifiedBrightness(_ value: Float, source: BrightnessSource) -> AppliedBrightness {
    let settings = BrightIntoshSettings.shared
    let deviceMax = getDeviceMaxBrightness()
    let clamped = max(0.0, min(deviceMax, value))

    if clamped <= 1.0 {
        // SDR zone — drive the system backlight, and disable XDR if it was on.
        SystemBrightnessControl.shared.write(level: clamped)
        if settings.brightintoshActive {
            settings.brightness = 1.0
            settings.brightintoshActive = false
        }
        return .applied
    }

    // XDR zone.
    if !settings.xdrWarningAcknowledged {
        switch source {
        case .cli:
            return .requiresGUIAck
        case .menuBar, .settings, .shortcut:
            let response = createXDRFirstUseAlert().runModal()
            // NSAlert button indexes: first button = .alertFirstButtonReturn
            guard response == .alertFirstButtonReturn else {
                return .cancelled
            }
            settings.xdrWarningAcknowledged = true
        }
    }

    // The CLI runs in a short-lived separate process and communicates with
    // the running main app through shared UserDefaults. Only `cliBrightness`
    // and `active` are KVO'd by the main app, so write those keys for a
    // CLI source rather than `brightness`.
    switch source {
    case .cli:
        settings.cliBrightness = clamped
        if !settings.brightintoshActive {
            settings.brightintoshActive = true
        }
    case .menuBar, .settings, .shortcut:
        settings.brightness = clamped
        if !settings.brightintoshActive {
            settings.brightintoshActive = true
        }
    }
    return .applied
}

/// Returns the unified slider value `[0.0, deviceMax]` that reflects the
/// app's current state:
///   - XDR active → return the current XDR `brightness` (>= 1.0).
///   - otherwise  → return the system backlight level (0.0–1.0), or
///                  `1.0` if CoreDisplay is unavailable.
@MainActor
func currentUnifiedBrightness() -> Float {
    let settings = BrightIntoshSettings.shared
    if settings.brightintoshActive && settings.brightness > 1.0 {
        return settings.brightness
    }
    return SystemBrightnessControl.shared.read() ?? 1.0
}

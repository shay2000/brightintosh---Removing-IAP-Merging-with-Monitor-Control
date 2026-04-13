//
//  HDRDeviceSupport.swift
//  HDRCore (isolated from BrightIntosh)
//
//  Original code by Niklas Rousset, extracted here so it can be reused
//  outside of BrightIntosh without pulling in settings, auth, or IAP code.
//
//  This file is equivalent to the device-detection portion of
//  BrightIntosh's `Constants.swift` + `Utils.swift`, but self-contained.
//

import Cocoa
import IOKit

/// Built-in MacBook Pro / MacBook Air / Mac Studio / iMac models that ship
/// with an XDR-capable display. Keep in sync with BrightIntosh upstream
/// (`Constants.swift`).
public let hdrSupportedDevices: [String] = [
    "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4",
    "Mac14,6", "Mac14,10", "Mac14,5", "Mac14,9",
    "Mac15,7", "Mac15,9", "Mac15,11", "Mac15,6", "Mac15,8", "Mac15,10", "Mac15,3",
    "Mac16,1", "Mac16,6", "Mac16,8", "Mac16,7", "Mac16,5",
    "Mac17,2", "Mac17,6", "Mac17,8", "Mac17,7", "Mac17,9"
]

/// Models whose MAX gamma multiplier is 1.535 (the so-called "SDR 600 nits"
/// variants — M3 and newer). All others max out at 1.59.
public let hdrSdr600nitsDevices: [String] = [
    "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11",
    "Mac16,1", "Mac16,6", "Mac16,8", "Mac16,7", "Mac16,5",
    "Mac17,2", "Mac17,6", "Mac17,8", "Mac17,7", "Mac17,9"
]

/// External displays that are XDR capable (by localized screen name).
#if DEBUG
public let hdrExternalXdrDisplays: [String] = ["Pro Display XDR", "Studio Display XDR", "C34H89x"]
#else
public let hdrExternalXdrDisplays: [String] = ["Pro Display XDR", "Studio Display XDR"]
#endif

/// Reads the `model` property out of the IOPlatformExpertDevice IORegistry
/// node — e.g. `"MacBookPro18,3"`.
public func hdrGetModelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    defer { IOObjectRelease(service) }

    if let modelData = IORegistryEntryCreateCFProperty(
        service, "model" as CFString, kCFAllocatorDefault, 0
    ).takeRetainedValue() as? Data {
        return String(data: modelData, encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters)
    }
    return nil
}

/// `true` iff the currently running Mac is in the built-in XDR support list.
public func hdrIsDeviceSupported() -> Bool {
    if let device = hdrGetModelIdentifier(), hdrSupportedDevices.contains(device) {
        return true
    }
    return false
}

/// Returns the maximum gamma multiplier for this device — usually `1.59`,
/// or `1.535` on "SDR 600 nits" (M3+) machines.
public func hdrGetDeviceMaxBrightness() -> Float {
    if let device = hdrGetModelIdentifier(), hdrSdr600nitsDevices.contains(device) {
        return 1.535
    }
    return 1.59
}

/// Returns `true` if the given `NSScreen` is the machine's built-in display.
public func hdrIsBuiltInScreen(screen: NSScreen) -> Bool {
    guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        return false
    }
    return CGDisplayIsBuiltin(screenNumber) != 0
}

/// Enumerates the currently attached screens and returns the subset that
/// are eligible for XDR brightening.
///
/// - Parameter onlyBuiltIn: when true, external XDR displays are excluded
///                          even if connected. Matches BrightIntosh's
///                          `brightIntoshOnlyOnBuiltIn` setting.
@MainActor
public func hdrGetXDRDisplays(onlyBuiltIn: Bool = false) -> [NSScreen] {
    var xdrScreens: [NSScreen] = []
    for screen in NSScreen.screens {
        let builtIn = hdrIsBuiltInScreen(screen: screen) && hdrIsDeviceSupported()
        let externalXdr = hdrExternalXdrDisplays.contains(screen.localizedName) && !onlyBuiltIn
        if builtIn || externalXdr {
            xdrScreens.append(screen)
        }
    }
    return xdrScreens
}

/// Convenience accessor for the `CGDirectDisplayID` of an `NSScreen`.
public extension NSScreen {
    var hdrDisplayId: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}

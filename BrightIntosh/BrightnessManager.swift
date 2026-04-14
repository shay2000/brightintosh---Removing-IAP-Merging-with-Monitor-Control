//
//  BrightnessManager.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.10.23.
//
//  Thin adapter over `HDRBrightnessController.shared` (see the isolated
//  HDRCore module). This class used to own its own `BrightnessTechnique`
//  and manage screens directly; that behaviour now lives inside HDRCore.
//  The adapter preserves BrightIntosh's app-level wiring:
//
//    - `BrightIntoshSettings` listeners drive enable/disable/brightness
//    - `Authorizer.shared` still gates activation on the Store Edition
//    - `NSApplication.didChangeScreenParametersNotification` and
//      `NSWorkspace.screensDidWakeNotification` are forwarded into HDRCore.
//

import Foundation
import Cocoa
import Combine

@MainActor
class BrightnessManager {

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Mirror the current `onlyOnBuiltIn` setting into HDRCore before we
        // attach any listeners, so initial enable uses the correct screen set.
        HDRBrightnessController.shared.onlyOnBuiltIn = BrightIntoshSettings.shared.brightIntoshOnlyOnBuiltIn
        HDRBrightnessController.shared.setBrightness(BrightIntoshSettings.shared.brightness)

        if BrightIntoshSettings.shared.brightintoshActive {
            activateSafely()
        }

        // Observe displays
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParameters(notification:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Observe workspace for wake notification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensWake(notification:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        // Observe entitlement
        Authorizer.shared.$status.sink { newStatus in
            if newStatus == .unauthorized && BrightIntoshSettings.shared.brightintoshActive {
                BrightIntoshSettings.shared.brightintoshActive = false
            }
        }.store(in: &cancellables)

        // Add settings listeners
        BrightIntoshSettings.shared.addListener(setting: "brightintoshActive") { [weak self] in
            guard let self = self else { return }
            if BrightIntoshSettings.shared.brightintoshActive {
                self.activateSafely()
            } else {
                HDRBrightnessController.shared.disable()
            }
        }

        BrightIntoshSettings.shared.addListener(setting: "brightness") {
            let newValue = BrightIntoshSettings.shared.brightness
            print("Set brightness to \(newValue)")
            HDRBrightnessController.shared.setBrightness(newValue)
        }

        BrightIntoshSettings.shared.addListener(setting: "brightIntoshOnlyOnBuiltIn") {
            HDRBrightnessController.shared.onlyOnBuiltIn = BrightIntoshSettings.shared.brightIntoshOnlyOnBuiltIn
        }
    }

    /// Enable the XDR overlay only if the user is currently allowed to use
    /// the extended range (Store Edition trial/entitlement check).
    func activateSafely() {
        if Authorizer.shared.isAllowed() {
            // Clamp out-of-range values before enabling.
            let safeBrightness = max(1.0, min(getDeviceMaxBrightness(), BrightIntoshSettings.shared.brightness))
            if safeBrightness != BrightIntoshSettings.shared.brightness {
                print("Fixing brightness")
                BrightIntoshSettings.shared.brightness = safeBrightness
            }
            HDRBrightnessController.shared.setBrightness(safeBrightness)
            HDRBrightnessController.shared.enable()
        } else {
            BrightIntoshSettings.shared.brightintoshActive = false
        }
    }

    @MainActor @objc func handleScreenParameters(notification: Notification) {
        HDRBrightnessController.shared.handleScreenParametersChanged()
    }

    @objc func screensWake(notification: Notification) {
        print("Wake up \(notification.name)")
        HDRBrightnessController.shared.handleScreensDidWake()
    }
}

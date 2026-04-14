//
//  Alerts.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 02.10.23.
//

import Foundation
import Cocoa

@MainActor func createBatteryAutomationContradictionAlert() -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "Your battery level is below \(BrightIntoshSettings.shared.batteryAutomationThreshold)%. Do you want to activate increased brightness anyway?\n\nThis will disable the battery automation."
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    return alert
}

/// One-time warning shown the first time the user drags the unified
/// brightness slider above the 100% tick into the XDR extended range.
@MainActor func createXDRFirstUseAlert() -> NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("Enable XDR extended brightness?",
                                          comment: "Title of first-use XDR warning alert")
    alert.informativeText = NSLocalizedString(
        "XDR mode drives your display significantly brighter than Apple's default maximum.\n\nSustained use can cause eye strain, higher power consumption, and noticeably warmer panel temperatures. It may also shorten display lifetime on some models.\n\nYou can disable XDR any time by moving the slider back below 100%.",
        comment: "Body of first-use XDR warning alert")
    alert.alertStyle = .warning
    alert.addButton(withTitle: NSLocalizedString("Enable XDR",
                                                 comment: "Confirm button on first-use XDR warning"))
    alert.addButton(withTitle: NSLocalizedString("Cancel",
                                                 comment: "Cancel button on first-use XDR warning"))
    return alert
}

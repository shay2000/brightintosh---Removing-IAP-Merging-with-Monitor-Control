# HDRCore — Isolated XDR/HDR Brightening Module

This directory contains the **isolated, self-contained code** extracted from
BrightIntosh that is responsible for forcing a Mac's built-in XDR display
(and compatible external XDR displays) into the full 1000-nit HDR brightness
range outside of HDR video playback.

This module was extracted so it can be reused by other projects (e.g.
XDRMonitorControl / MonitorControl) without pulling in any of BrightIntosh's
licensing, StoreKit, trial, settings, UI, or widget code.

---

## How the HDR/XDR brightening works

macOS normally only permits the full HDR brightness range on XDR-capable
displays while HDR content is on screen (HDR video, HDR photos, etc.).
BrightIntosh's technique fools macOS into keeping that extended range
active at all times, by combining two tricks:

### 1. A transparent Metal overlay with `wantsExtendedDynamicRangeContent`

For every XDR-capable screen, a 1×1 px borderless `NSWindow` is created
at the screen's origin. That window contains an `MTKView` whose
`CAMetalLayer` is configured as:

```swift
layer.wantsExtendedDynamicRangeContent = true
layer.pixelFormat = .rgba16Float
```

with `colorspace = CGColorSpace(name: .extendedLinearSRGB)` and a clear
color whose components are > 1.0 (values outside the SDR [0, 1] range).

This combination tells macOS "there is HDR content being rendered on this
screen", which causes the display to enter the extended dynamic range mode
and unlock the full 1000-nit brightness range.

See `HDRMetalOverlay.swift` and `HDROverlayWindow.swift`.

### 2. A gamma-table multiplier

While the display is in HDR mode, the gamma LUT is scaled by a factor
(typically 1.0–1.59, depending on the Mac model) using
`CGSetDisplayTransferByTable`. This boosts *everything* on the screen
brighter, effectively acting as a global brightness slider above 100%.

See `HDRBrightnessTechnique.swift` (`GammaTable` + `GammaTechnique`).

### 3. Re-apply on screen wake / reconfigure

The gamma LUT is reset by macOS on screen wake or display reconfiguration,
so the controller listens to the appropriate notifications and re-applies
the table when needed. See `HDRBrightnessController.swift`.

---

## File map

| File | Purpose |
|------|---------|
| `HDRDeviceSupport.swift` | Identifier / model detection, supported-device lists, max-brightness factor lookup. |
| `HDRMetalOverlay.swift` | `MTKView` subclass that renders the EDR content. |
| `HDROverlayWindow.swift` | `NSWindow` + `NSWindowController` that hosts the metal overlay per display. |
| `HDRBrightnessTechnique.swift` | `GammaTable` helper and `GammaTechnique` class — the heart of the brightening. |
| `HDRBrightnessController.swift` | High-level, singleton-style controller an integrator talks to. |

---

## Integration (in a nutshell)

```swift
// Enable HDR brightening at 1.5× (50% above SDR) on all XDR displays:
HDRBrightnessController.shared.setBrightness(1.5)
HDRBrightnessController.shared.enable()

// Later, turn it off:
HDRBrightnessController.shared.disable()
```

The integrator is expected to:

1. Hook `NSApplication.didChangeScreenParametersNotification` and call
   `HDRBrightnessController.shared.handleScreenParametersChanged()`.
2. Hook `NSWorkspace.screensDidWakeNotification` and call
   `HDRBrightnessController.shared.handleScreensDidWake()`.

---

## What was *intentionally* left out

- `BrightIntoshSettings.swift` (UserDefaults singleton)
- `Authorizer.swift`, `EntitlementHandler.swift`, `Trial.swift`, `StoreManager.swift`
- `BrightnessManager.swift` (replaced by the simpler `HDRBrightnessController`)
- All SwiftUI / AppKit settings UI
- The CLI, widgets, automation, localized strings, StoreKit configuration

The only thing that remains is the **pure mechanism** that lifts a Mac
display into extended dynamic range and scales its gamma output.

---

## Credit

Original code by Niklas Rousset (BrightIntosh),
licensed under the GNU GPL v3. Any downstream user of this
isolated module must remain compliant with the GPL.

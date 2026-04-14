
<p align="center">
  <img width="256" height="256" alt="BrightIntosh-iOS-Default-256x256@1x" src="https://github.com/user-attachments/assets/02136d9a-11e1-49f8-bd16-8c23fe02acfc" />
</p>
<p align="center">
  <a href="https://www.brightintosh.de">View our website</a><br/><br/>
  <a href="https://apps.apple.com/app/apple-store/id6452471855?pt=126521145&ct=github&mt=8" style="display: inline-block;">
    <img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1693267200" alt="Download on the App Store" style="width: 246px; height: 82px; vertical-align: middle; object-fit: contain;" />
  </a>
</p>

> [!WARNING]
> **This is a modified, unofficial fork of BrightIntosh.**
>
> This branch (`claude/merge-xdr-controls-X8e3Y`) contains experimental
> changes that **merge MonitorControl-style system brightness control with
> BrightIntosh's XDR gamma boost into a single unified slider**. Below
> 100% the slider drives the macOS internal-display backlight via a
> private CoreDisplay API; at or above 100% it drives the XDR gamma
> boost. A one-time warning is shown the first time you cross into the
> XDR zone.
>
> This code is **not affiliated with or endorsed by the upstream
> BrightIntosh project or its authors**, has **not been reviewed or
> released by them**, and is **not the version distributed on the Mac
> App Store**. Use at your own risk. The official, supported app
> remains the upstream release linked above.
>
> Notable deviations from upstream:
> - Unified slider spanning system brightness (0–100%) and XDR (100%+).
> - First-use XDR warning gated by `xdrWarningAcknowledged`.
> - Sub-100% control uses the private `CoreDisplay_Display_SetUserBrightness`
>   symbol (dlopen'd at runtime); may break on future macOS versions.
> - External non-Apple display brightness below 100% is **not**
>   implemented (DDC/i2c is a deferred follow-up).
> - The legacy `BrightnessTechnique.swift` has been removed in favour
>   of the extracted `HDRCore` module.
> - IAP / Store Edition gating is **untouched** in this branch.

# BrightIntosh

BrightIntosh enables your MacBook Pro M1 (or newer) to use the increased brightness (1000 nits) of its XDR display at any time. By default, this is only possible when displaying HDR content.
BrightIntosh can shift your brightness range to higher values.
The brightness slider in the app controls how much you shift this range.
You can still use your brightness keys to control the brightness.
It comes with a handy menu bar item so you can toggle the increased brightness quickly and easily.

> [!IMPORTANT]
> This tool should not harm your display as it doesn't use any low-level API calls and your OS is in full control over the display, but there is no warranty.

## Preview

<p align="center">
  <img src="https://github.com/niklasr22/BrightIntosh/assets/75939868/b8774d5c-7bfa-4661-86d0-e0e58fefbdf1">
</p>

Maximum brightness with BrightIntosh on the left half of the picture, default maximum brightness on the right half.

## Installation

- [Mac App Store](https://apple.co/3r0Ghqm)
- 👩🏼‍💻 Build it yourself 👨🏽‍💻

## Contributing

If you have any ideas, enhancements or proposals, feel free to open an issue!

## Known incompatibilities and problems:

- BrightIntosh and [f.lux](https://justgetflux.com) will likely not work simultaneously
- HDR Videos will clip when BrightIntosh is active

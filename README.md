# Resize

A macOS menu bar app that sets the zoom of your browsers, terminals, and editors for you. Plug into a
bigger screen and your chosen apps zoom in; unplug and they go back.

- Pick the apps you care about.
- Set a **default zoom** for the laptop screen and for an external monitor (for example 100% and 125%).
- Give single apps their own zoom if they need something different.
- Resize notices when you connect or disconnect a display, and when a managed app launches, and applies the right zoom.

Any external display counts as "External", whether the lid is open or closed.

## Build and run

Requires macOS 14+ and Xcode (for the SwiftUI and AppKit SDKs).

```bash
scripts/run.sh          # builds build/Resize.app and launches it
swift test              # unit tests for the logic layer
```

`scripts/bundle.sh [debug|release]` builds `build/Resize.app` without launching it. Running from the `.app`
matters: "Launch at login" and the menu bar behavior only work in a real bundle.

### Accessibility permission

Resize changes zoom by pressing keyboard shortcuts (⌘0, ⌘=, ⌘-) in your apps, which needs
**System Settings → Privacy & Security → Accessibility**. The app asks on first launch.

> **Development gotcha:** with ad-hoc signing, a rebuild can invalidate the Accessibility grant. If zoom
> stops working after a rebuild, remove Resize from the Accessibility list and add it again.

## How it works

Every way of zooming an app is a `ZoomDriver`. Today there is one, `KeystrokeDriver`, which works for
any app: it brings the app to the front, resets zoom with ⌘0, then presses ⌘= or ⌘- the right number of
times. More exact drivers (scripting, config files, a browser extension) can be registered ahead of it in
`DriverRegistry` without changing anything else. See [docs/PLAN.md](docs/PLAN.md) for the design and roadmap.

```
Sources/ResizeKit/   logic: model, config store, display/app monitors, drivers, coordinator (unit tested)
Sources/Resize/      SwiftUI app: menu bar popover, settings window, onboarding
```

## Supported apps

Any app that handles ⌘0 / ⌘= / ⌘- works. These have tuned zoom steps:

| Kind | Apps |
|---|---|
| Browsers | Chrome, Safari, Firefox, Edge, Brave, Arc, Vivaldi, Opera |
| Terminals | Terminal, iTerm2, Ghostty, kitty, Alacritty, WezTerm, Warp |
| Editors | VS Code, Cursor |

Step sizes for kitty, Alacritty, WezTerm, and Warp are best guesses and marked `TODO verify` in
`KeystrokeProfiles.swift`.

## Known limitations

- **Keystroke zoom affects only the focused window or tab.** Browsers also remember zoom per website.
  A browser extension driver is planned to make browser zoom app-wide.
- **Apps briefly come to the front** while their zoom is applied; focus returns to where you were.
- Zoom lands on the app's own steps, so the result can be slightly off the requested value. The app
  detail page shows "≈ N% reached".
- Apps with no open window ignore the shortcuts.
- Nothing is applied while the screen is locked; it runs after you unlock.

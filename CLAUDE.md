# Resize

Native macOS menu bar app that automatically sets per-app zoom (browsers, terminals, editors) depending on
whether an external display is connected.

**Read `docs/PLAN.md` before doing anything.** It holds the full context, the decisions already made,
and the step-by-step implementation plan. Follow the steps in order, and keep `swift build` and `swift test`
green after each step.

Key rules:
- Swift Package Manager only (no .xcodeproj). Logic goes in `ResizeKit` (testable); SwiftUI goes in `Resize`.
- macOS 14+, no App Sandbox, Accessibility permission required.
- Zoom is per app, stored as a percentage; two display modes only: `laptop` and `external`.
- Every zoom mechanism is a `ZoomDriver`. `KeystrokeDriver` is the universal fallback and is always last in the registry.
- Build/run the app via `scripts/run.sh` (wraps the SPM binary into `build/Resize.app`).
- Don't commit to `master`/`main` directly; use a feature branch.

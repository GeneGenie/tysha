# Тиша (internal name: BreathOS)

iOS 17+ SwiftUI + Metal breathing app (Wim Hof style). Russian UI, dark theme,
local device install only. Full spec: `BreathOS_TЗ.md`. Display name is
**Тиша**; the Xcode target/folder stay `BreathOS` — don't rename them.

UI is localized via `<lang>.lproj/Localizable.strings` (**uk** = default/dev region, **ru**, **en**), looked up through the `L("key")` helper in `Localization.swift`. Language follows the device. App display name is a single brand "Тиша" (not localized). When adding UI text: add the key to all three `.strings` files. Standalone model test now needs `Localization.swift` too: `swiftc BreathModels.swift AudioConfig.swift Localization.swift <test>.swift`.

## Build & verify

```bash
xcodebuild -project BreathOS.xcodeproj -scheme BreathOS -sdk iphoneos \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -destination 'generic/platform=iOS' -quiet build
```

Always compile-verify with this after changes (full Xcode is installed). The user
runs on a physical iPhone from Xcode (free signing, 7-day expiry). Pure model
logic (`buildQueue`, `adjustedHoldOut`) can be tested standalone:
`swiftc BreathOS/BreathModels.swift BreathOS/AudioConfig.swift <test>.swift`.

## Architecture

- `BreathModels.swift` — `BreathPhase`, `BreathSettings` (UserDefaults JSON), flat phase-queue builder. Each round: N×(inhale+exhale) → holdOut → recovery inhale → holdIn → final 4s exhale.
- `BreathEngine.swift` — `@Observable`; CADisplayLink timing, haptics (`HapticManager`), audio (`AudioManager`). Engine publishes `shaderPhase`/`shaderPrevPhase` (visual mapping) separately from `phase` (logical).
- `Breath.metal` — `breathBackground` colorEffect: flash (0), fractal (1,2), hold-out black waves (3), crossfade via `transition`.
- `BreathShaderView.swift` — TimelineView → uniforms. `SettingsView` / `SessionView` / `BreathOSApp.swift` (incl. 2s `SplashView`).
- `AudioConfig.swift` — **developer defaults only**; user-facing volumes live in `BreathSettings` (Settings screen sliders).

## Hard-won gotchas (don't re-learn these)

- **Shader radial coords**: use `cn` (normalized so 1.0 = screen corner). Raw centered coords max out at ~0.55 on portrait screens — caused "vignette never appears" bug.
- **No radial advection in noise** (`dir * t`): shears the field over time into spikes pointing at center. Drift noise uniformly instead.
- **Visual ≠ logical phase**: the breath series always renders the fractal (no per-breath flash); flash only for recovery inhale (`breathIndex == nil`); hold-out enters with `transitionInstant` (no crossfade) and its base fractal uses the same drift speed as exhale for a seamless cut.
- **AVAudioPlayer rate floor is 0.5** — can't stretch 1.5s exhale to 4s at runtime; `exhale_long.mp3` is pre-stretched via `ffmpeg -filter:a atempo` (ffmpeg at `~/homebrew/bin/ffmpeg`).
- **BreathSettings decoding uses `decodeIfPresent` per field** — new fields MUST follow this pattern or saved settings get wiped. Never change `storageKey` ("BreathSettings.v1").
- **pbxproj is hand-written** (deterministic UUIDs: AA=project infra, BB=file refs, CC=build files). Adding a bundle resource = 4 edits: PBXBuildFile, PBXFileReference, group children, Resources build phase.
- **Launch screen**: `Info.plist → UILaunchScreen` (merged with GENERATE_INFOPLIST_FILE). iOS caches splashes — reinstall the app to see changes. Splash duration isn't configurable; the in-app `SplashView` tops it up to 2s total.
- `git stash` may hold a "soft fog/cloud hold-out shader" variant that was rejected ("nothing happens" — too slow). If revisiting, keep v1's motion speed, soften only the edge.

## User preferences (important)

- **Never update README.md or any docs unless explicitly asked.**
- No Co-Authored-By lines in commits.
- UAT discipline: build + show real output before claiming done; verify in the built bundle (`plutil -p .../Info.plist`, `xcrun assetutil --info .../Assets.car`) when touching assets/plist.
- Designer source assets live in `brand/` (logo.PNG 1024², splash.PNG 848×1264). Icon needs opaque 1024²; splash is scale-fill center-cropped to 1290×2796 (@3x) + 860×1864 (@2x) in `LaunchSplash.imageset`.

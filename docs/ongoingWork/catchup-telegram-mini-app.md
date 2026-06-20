# Catchup: «Тиша» → Telegram Mini App (from scratch)

## Focus (user guidance — what THIS resume is about)

The user wants to **rebuild the «Тиша» breathing app as a Telegram Mini App inside a bot**, from scratch:
- Stack: **Node.js + "gram.js"**, deploy on **Railway.com**.
- The user has **never built a Telegram app before** and explicitly wants to:
  1. **Discuss the app design** for the Telegram context (not just start coding).
  2. **Learn the подводные камни (pitfalls)** of TG Mini Apps.

> **Next session must LEAD WITH DISCUSSION + PITFALLS, not code.** Open by clarifying
> the framework ambiguity (below), then walk the pitfalls, agree an architecture, then scaffold.

The existing **native iOS app is the reference/source-of-truth for the UX and logic** to port — it is finished and works. The Telegram app reimplements the same experience on the web.

---

## ⚠️ Pitfall #0 — clarify "gram.js" FIRST

"gram.js" is ambiguous and it changes the whole architecture:
- **GramJS** (`telegram` npm) = an **MTProto client** (acts as a user/bot client at the low level). **Not** the normal way to build Mini Apps.
- **grammY** (sounds like "gram.js") = a popular **Bot API** framework — the normal choice for the bot side.

For a **Mini App**, the standard architecture is:
1. A **bot** (Bot API via grammY/telegraf) that shows a button to launch the Mini App (`web_app` keyboard button or the chat **Menu Button**).
2. The **Mini App itself = a web page** served over **HTTPS**, running inside Telegram's in-app webview, using the **Telegram WebApp SDK** (`window.Telegram.WebApp` / `telegram-web-app.js`).
3. A small **Node backend** to validate `initData` and (optionally) persist settings.

**Recommendation to propose:** grammY for the bot + a static web Mini App + tiny Node backend, all in one Railway service. Confirm whether the user truly wants GramJS/MTProto (rarely needed here) or just meant "a Telegram bot in Node".

---

## TG Mini App pitfalls relevant to THIS app (discussion agenda)

This is a **timed breathing session** (2–8 rounds, long breath-holds up to 180s, precise audio + haptics, full-screen animated background, screen must stay awake). The webview context fights several of those:

1. **Screen wake / lock** — biggest risk. No reliable "keep screen on" in a Telegram webview. `navigator.wakeLock` support is spotty inside Telegram. A 180s hold with the screen dimming/locking ruins the UX. Discuss mitigations (Wake Lock attempt + fallback guidance, or accept it).
2. **Background throttling** — when the user leaves the chat/app, JS timers and audio are throttled/suspended. The iOS version deliberately keeps the screen awake to avoid this (`isIdleTimerDisabled`); webview can't. Use `performance.now()` + `requestAnimationFrame` for timing and handle visibility loss gracefully (pause/resume).
3. **Audio** — webview autoplay needs a **user gesture**; preload + "unlock" all `Audio()` players on the Start tap. Background audio won't play. The bg-music + per-phase cues + 4s long-exhale all need this unlock pattern.
4. **Haptics** — Telegram WebApp SDK has `HapticFeedback` (`impactOccurred('light'|'medium'|'heavy'|'rigid'|'soft')`, `notificationOccurred('success'|...)`). Maps reasonably to the current schedule, **but only works in official mobile clients** (not desktop/web). Plan a no-op fallback.
5. **Background shader** — port `Breath.metal` → a **WebGL GLSL fragment shader** (the math is portable: same FBM, domain-warp, central flash, black-wave hold-out, phase crossfade). Or Canvas2D fallback.
6. **Fullscreen** — Mini Apps historically only `expand()` (not true fullscreen); real fullscreen arrived in **Bot API 8.0** (`requestFullscreen`). Gate on version; design for the expanded (not fullscreen) case too.
7. **HTTPS** — Mini App URL must be HTTPS. Railway provides it. Good.
8. **initData validation** — validate the `initData` HMAC-SHA256 with the bot token **server-side** before trusting the user/identity.
9. **Settings persistence** — Telegram **CloudStorage** API (per-user, synced) or `localStorage`, or a backend DB. iOS used `UserDefaults`; CloudStorage is the closest analog.
10. **Theme** — respect `Telegram.WebApp.themeParams` (the app is dark-themed; force/honor dark).

---

## Existing iOS app = reference for the port (logic source of truth)

The session model, schedule and visuals are fully specified in code. Port these — do not redesign the breathing logic.

| File | Purpose |
|------|---------|
| `BreathOS_TЗ.md` | Original full spec (Russian) — session model, phases, visuals, haptics, audio. >200 lines; read fully when porting. |
| `BreathOS/BreathModels.swift` | **Session structure source of truth** (180 lines): `BreathPhase` (inhale/holdIn/exhale/holdOut), `BreathSettings` (defaults + ranges + tolerant decode), `adjustedHoldOut`, and `buildQueue()` — each round = N×(inhale+exhale) → holdOut → recovery inhale → holdIn → **final 4s exhale**. |
| `BreathOS/BreathEngine.swift:37-92` | `HapticManager` — incl. `holdMarker()` (4× medium) and `countdownTick()` (4× light) bursts. |
| `BreathOS/BreathEngine.swift:94-180` | `AudioManager` — per-phase players + volumes, bg-music loop from offset, `playLongExhale`. |
| `BreathOS/BreathEngine.swift:276-360` | `shaderIndex(for:)` (steady fractal during series, flash only on recovery inhale), `beginStep`, `tick`, `holdOutHaptics` (double-pulse every 15s; 4× each of last 3s), `advance`. |
| `BreathOS/Breath.metal:47-138` | Shader to port to GLSL: `warpedField` (FBM+domain warp), `renderFractal`, `renderFlash`, `renderHoldOut` (soft black waves), `renderPhase` dispatch, `breathBackground` entry + crossfade. |
| `BreathOS/AudioConfig.swift` | Dev defaults: bg music start **90s**, music vol 0.55, breath vol 0.4 (8 lines). |
| `BreathOS/uk.lproj/Localizable.strings` | **uk/ru/en translations to reuse for web i18n** (also `ru.lproj`, `en.lproj`). uk = default. |

Behavior already tuned (replicate exactly): app name **«Тиша»**; 3 languages **uk(default)/ru/en**; safety warning shown on both screens (wording = "sitting"); hold-out background = **soft black waves** (keep v1 churn speed — a slow "fog" variant was rejected as "nothing happens"); haptics = heavy on every phase change, soft pulse at hold-out start/end, **4× medium every 15s**, **4× light each of the last 3s**; **final 4s exhale closes each round** (pre-stretched `exhale_long.mp3`).

---

## Current repo state (decide before starting TG work)

- Branch `main`. Last commit **`28a012c` (v3)**.
- **All the latest iOS work is UNCOMMITTED** in the working tree: «Тиша» rename, bundle id `com.metamanafamily.silencio`, full uk/ru/en localization (`Localization.swift`, `*.lproj/`), `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption`, breaths-per-round slider, volume sliders, stronger hold-out haptics, restored localized warning.
- iOS build is verified clean (`xcodebuild … exit 0`); App-Store-ready.
- ⚠️ **Recommend committing the iOS state first** so it's preserved before the repo gains a Node app. Open question to ask: **same repo (subfolder, e.g. `telegram/`) vs a new repo** for the TG app. (Bundle-id spelling `metamanafamily` vs earlier `ManaMetaFamily` is still unconfirmed but only matters for the iOS App Store track.)

---

## TODO (next session, in order)

1. **Discussion-first** (no code yet): resolve Pitfall #0 (grammY vs GramJS), walk the pitfalls above, and agree the architecture + repo layout. This is the user's explicit ask.
2. Decide repo layout (subfolder vs new repo) and **commit the iOS work** if keeping same repo.
3. Scaffold the Node project: bot (launch button / menu button) + static Mini App served over HTTPS + `initData` validation endpoint.
4. Port the **session engine** (phase queue, durations, haptic/audio schedule) from `BreathModels.swift` / `BreathEngine.swift`.
5. Port the **background shader** `Breath.metal` → WebGL GLSL.
6. Wire the **Telegram WebApp SDK**: dark theme, HapticFeedback, CloudStorage settings, BackButton, expand()/fullscreen, MainButton for "Начать".
7. Reuse **uk/ru/en strings** for web i18n (uk default).
8. **Railway deploy**: one Node service, HTTPS URL → set as the bot's Mini App URL (BotFather / menu button). Verify end-to-end in the Telegram client.

## Carried-over user preferences

- **Never** edit README/docs unless explicitly asked (the user was annoyed by README churn).
- **No** `Co-Authored-By` lines in commits; don't commit/push unless asked.
- UAT discipline: build/run and show **real output** before claiming done.
- Be direct about trade-offs; for a discussion, give honest assessment + pitfalls, not a sales pitch (this whole task starts as a discussion).

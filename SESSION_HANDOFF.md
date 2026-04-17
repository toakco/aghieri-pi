# Aghieri Session Handoff

**Date:** 2026-04-17 (Symposium day)
**Branch:** `windows-batch-overhaul`
**Working directory:** `C:\Projects\aghieri`

---

## What was done

11-batch overhaul of the Aghieri Flutter app (ADHD productivity capstone for NC State DS-483). All batches executed autonomously on `windows-batch-overhaul` branch. Every batch passed `flutter analyze` (only pre-existing error: `test/widget_test.dart` references `MyApp` which doesn't exist). `flutter build web --release` succeeds.

### Batch Summary

| # | Batch | Commit | Key Files |
|---|-------|--------|-----------|
| 1 | Onboarding fixes | 808b1e3 | `lib/features/onboarding/onboarding_screen.dart` |
| 2 | Terms of Service gate | 27a2a7b | `lib/features/onboarding/terms_screen.dart`, `lib/app.dart`, `lib/models/user_profile.dart`, `lib/services/profile_service.dart` |
| 3 | Task creation (endDate) | 1a8f243 | `lib/models/task_model.dart`, `lib/services/task_service.dart`, `lib/features/tasks/tasks_screen.dart` |
| 4 | Moon wedge opacity | 8325bd0 | `lib/widgets/circular_display/circular_arc_display.dart` |
| 5 | Focus screen overhaul | 51d8639 | `lib/features/focus/focus_screen.dart`, `web/index.html` |
| 6 | Wake-up routine | f4a3b1b | `lib/features/alarms/wakeup_routine.dart`, `lib/services/alarm_service.dart`, `lib/features/alarms/alarms_screen.dart` |
| 7 | Insights subpages | b198ce7 | `lib/features/portfolio/portfolio_screen.dart`, `lib/services/claude_service.dart` |
| 8 | Voice state ring | 0a41ae3 | `lib/widgets/voice_state_ring.dart`, `lib/services/voice_service.dart`, `lib/features/home/home_screen.dart` |
| 9 | Settings polish | eace835 | `lib/features/settings/settings_screen.dart`, `lib/features/integrations/integrations_screen.dart` |
| 10 | Profile photo upload | 1393e85 | `lib/features/profile/profile_screen.dart`, `lib/models/user_profile.dart` |
| 11 | Music service | a84e25d | `lib/services/music_service.dart`, `lib/widgets/now_playing_card.dart`, `lib/main.dart` |

### What each batch did (details in `PROGRESS.md`)

- **B1:** Button font size match, default typography to adaptive
- **B2:** ToS screen (gate + read-only), router guard, Firestore `tosAcceptedAt`
- **B3:** `endDate` on tasks, `isMultiDay` getter, date range in creation dialog
- **B4:** `canvas.saveLayer` per-stripe opacity — multi-day pulse 0.35, active 0.85, default 0.70
- **B5:** Nunito 900 title, HSL complement color, +20px glow bleed, repositioned to 60% height
- **B6:** `WakeupRoutine` (Claude 45s briefing), `isWakeUp` on Alarm, sun icon + amber accent UI
- **B7:** `chat()` on ClaudeService, tappable insight cards → bottom sheet with AI description, Firestore cache 24h TTL
- **B8:** `VoiceState` enum + stream on VoiceService, `VoiceStateRing` widget (4 animated states), overlaid on moon clock
- **B9:** Connected Services section (green checkmarks), QR pairing dialog, "Your data" link
- **B10:** `avatarUrl` on UserProfile, file_picker → Firebase Storage upload, CachedNetworkImage
- **B11:** `MusicService` (ambient, ducking, fade-in/out), `NowPlayingCard`, music intent classification

---

## Current state

- All 11 batches complete and committed
- `flutter build web --release` succeeds (build/web output)
- Branch has NOT been pushed or merged to main
- PROGRESS.md is up to date
- **DEPLOYED to Firebase Hosting 2026-04-17 (symposium day) — live at https://aghieri-7a8ce.web.app**

## Deploy record — 2026-04-17 (post-overhaul redeploy: voice + device + auth)

- Rebuilt: `flutter build web --release` after fixing `AghieriColors.text` → `AghieriColors.textPrimary` in `lib/features/auth/sign_in_screen.dart:164`. Build succeeded (32.5s).
- Deployed: `firebase deploy --only hosting` → **Deploy complete!**
- Live URL: https://aghieri-7a8ce.web.app — HTTP 200, fresh `main.dart.js` confirmed.
- New surfaces shipped in this deploy:
  - `/device` — voice-first round display (CircularArcDisplay + VoiceStateRing) with wake word "Aghieri" + 3-min screensaver dim to 10% opacity
  - `/device/focus/:id` — task-focused circular UI with voice intents (next, done, home)
  - `/sign-in` — Google + Apple sign-in (anon → linked, preserves data)
  - `/auth/spotify/callback` + `/auth/notion/callback` — real OAuth via Cloud Functions
  - Settings tile linking to Sign-in
  - Path URL strategy enabled (no `#` in OAuth redirects)
- Cloud Functions deployed earlier in session: `voiceCommand` (max_tokens 100, minInstances 1, ANTHROPIC_KEY secret), `textToSpeech` (eleven_flash_v2_5, streaming-optimized URL params, minInstances 1, ELEVENLABS_API_KEY secret), `spotifyAuthStart/Callback`, `notionAuthStart/Callback`.
- Latency wins: STT pauseFor 4s → 1.2s, ElevenLabs turbo → flash_v2_5, voiceCommand max_tokens 180 → 100, warm Cloud Functions ($5-8/mo).
- Pi kiosk launch script at `scripts/aghieri-pi-kiosk.sh` (Chromium kiosk pointing at `/device`, mic auto-granted via fake-ui flag, autoplay enabled).
- macOS desktop build cannot run on Windows host — will execute on Mac handoff.

### Earlier deploy — symposium baseline (Batch 11 build)

- Rebuilt: `flutter build web --release` → `✓ Built build\web` (main.dart.js ~3.56 MB)
- Auth: `firebase projects:list` confirmed `aghieri-7a8ce` visible; `firebase use aghieri-7a8ce` active
- Deployed: `firebase deploy --only hosting` → **Deploy complete!**
- Hosting URL: https://aghieri-7a8ce.web.app (HTTP 200, serves fresh index.html)
- Server-side smoke checks passed:
  - `GET /` → 200, new index.html with Nunito 700/800/900 Google Fonts link (Batch 5 tell ✅)
  - `GET /flutter_bootstrap.js` → 200, 9975 bytes
  - `GET /main.dart.js` → 200, 3561779 bytes (fresh bundle)
- **Still required before demo:** Joey must open https://aghieri-7a8ce.web.app in a browser and click through onboarding → home (moon clock + voice ring) → tasks (endDate/multi-day) → focus (Nunito 900 title, complement glow) → insights (tappable cards) → alarms (wake-up sun icon) → profile (avatar upload). Server-side check can't visually verify these.

## What's next

1. **Joey: browser walkthrough** of the live demo before the symposium — confirm all 11 batch changes render correctly.
2. **PR to main** (optional, after symposium) — branch `windows-batch-overhaul` still not pushed. Ask before pushing.
3. **Higgsfield assembly instruction images** (separate task in `C:\Projects\Portfolio\01_Capstone_Aghieri`)
4. **Slides** at `C:\Projects\Portfolio\01_Capstone_Aghieri\aghieri_slides.html`

## Key technical context

- **Stack:** Flutter web + Firebase (project: aghieri-7a8ce)
- **GoRouter** with auth/ToS/onboarding guards in `lib/app.dart`
- **SharedPreferences** (local cache) + **Cloud Firestore** (authoritative store)
- **Claude API** routes through device backend at `192.168.1.100:8000`, falls back to mock
- **ElevenLabs** TTS (Antonio voice, hardcoded)
- **Design system:** ADHD-optimized — no red, 3 typography modes (default/classic/adaptive with OpenDyslexic)
- **Voice pipeline:** STT → Claude haiku → ElevenLabs TTS, with wake word "Aghieri"

## How to resume

In a new Claude Code terminal:

```
cd C:\Projects\aghieri
```

Then say:

> Read SESSION_HANDOFF.md and PROGRESS.md, then continue from where we left off. Order 66.

---

## File reference

| File | Purpose |
|------|---------|
| `BATCH_PLAN.md` | Original 11-batch specification |
| `PROGRESS.md` | Completion status per batch |
| `PROJECT_BRIEF.md` | Full project context |
| `SESSION_HANDOFF.md` | This file — session transfer |
| `lib/app.dart` | Router + 13 routes |
| `lib/main.dart` | App startup chain |
| `lib/core/theme/app_theme.dart` | Design system |
| `pubspec.yaml` | Dependencies |
| `firebase.json` | Hosting config |

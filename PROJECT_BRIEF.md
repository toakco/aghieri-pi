# Aghieri — Project Brief

ADHD productivity app. Flutter (Dart) for web, iOS, Linux desktop (Pi 5). Firebase backend (aghieri-7a8ce). NC State capstone, commercialized through TOAKCO LLC. Live: https://aghieri-7a8ce.web.app

## Capstone constraints (non-negotiable)
- No red in UI. Amber for warnings only.
- Ambient over alert. Peripheral vision, no harsh notifications.
- Subtraction is the design mechanism. When in doubt, remove.
- Calm tech (Weiser & Brown 1996). Information available, never demanding.
- No gamification ever. No streaks/badges/points/leaderboards.
- Voice-first where possible.
- ADHD accommodation, not adaptation.

## Locked architectural decisions
1. Moon clock tasks render as crescent wedges, not stripes. Wedges use dayFrac terminator math scoped to task time window. Multi-day = reduced opacity background wedges.
2. Night mode resets moon. White area regrows left→right during night. Full white by wake time.
3. Outer ring always lit with ambient white blob animation. Active task → ring shifts to task color. Voice states: green (listen), amber (think), blue (respond). Amplitude-reactive via Web Audio FFT.
4. Focus screen title: looped breathing wave animation, rounded font (Nunito 900), 80% height, color = HSL complement of task color.
5. API keys: auth-tied pre-provisioning in Firestore admin_keys/{uid}, security rules lock to request.auth.uid == uid. Joe's UID provisioned manually. No user-facing key input.
6. Voice locked to Antonio (ElevenLabs).
7. Typography defaults to Adaptive. No selection screen.
8. Music: Spotify Connect primary + yt-dlp fallback. Fully ambient — duck on voice, auto-play on focus, wind-down at sleep, fade-in before wake-up.
9. Hardware runs Flutter Linux desktop natively on Pi 5.
10. iOS build: Mac + Xcode. Bundle ID com.toakco.aghieri. TestFlight distribution.

## Architecture
- Router: GoRouter in lib/app.dart with auth/ToS/onboarding guards
- State: StatefulWidgets + singleton services
- Firestore: users/{uid}/tasks/{taskId}, Firebase Auth, Storage
- Voice pipeline: STT → Claude API → TTS in lib/services/voice_service.dart
- Music: lib/services/music_service.dart (Spotify + yt-dlp)

## Key files
- lib/widgets/circular_display/circular_arc_display.dart — moon clock wedge rendering
- lib/features/focus/focus_screen.dart — focus mode, animated title, steps
- lib/models/task_model.dart — includes endDate, isMultiDay, generated steps
- lib/services/voice_service.dart — voice pipeline with music ducking
- lib/services/music_service.dart — Spotify + yt-dlp control
- lib/services/api_keys_service.dart — Firestore-backed key retrieval, memory-cached only
- lib/core/theme/app_theme.dart — AghieriColors, AghieriTextStyles, Adaptive default

## Moon wedge spec
Main moon: Day shrinks left→right, night regrows left→right (mirrored). dayFrac 0→1 via _moonLitPath().

Task wedges (replaces stripes):
- startFrac = (task.scheduledTime - wakeTime) / (sleepTime - wakeTime)
- endFrac = (task.scheduledEndTime - wakeTime) / (sleepTime - wakeTime)
- Crescent between two terminators, clipped to lit moon. task.color at 0.7 opacity.
- Multi-day: 0.35 opacity with slow pulse (sin wave, 4s period).
- Active task: 0.85 opacity + lava lamp blob animation from focus screen.
- Tab-aware: Today uses wake→sleep window; Week/Month/Year scale proportionally.
- Hit test: Path.contains() → navigate /focus/{taskId}.

Outer ring:
- 8px wide, always visible.
- Default: white ambient blobs.
- Active task: ring color = active task color.
- Voice states separate overlay: LISTENING green #7BC97B (amplitude-reactive), THINKING amber #E8B86D (slow rotation), RESPONDING blue #6DA8E8 (amplitude-reactive on TTS).

Preserve: 3D sphere rendering, specular highlight, atmospheric rim, ambient occlusion, _MoonRng deterministic blob seeding.

## Music ambient rules (music_service.dart)
- Wake-up: fade in 5 min before alarm, 10%→60% by alarm time. Wake-up playlist or gentle default.
- Focus start: auto-play focus playlist at 50%.
- Voice activity: duck to 15% over 200ms. Restore 1s after idle.
- Break (Aquarium): ambient/nature playlist.
- Wind-down: 30 min before sleep, shift to low-energy tracks (Spotify audio features: energy<0.4, valence>0.4, tempo<100), fade to 0 by sleep.
- Never during: active non-wake-up alarms, notifications, onboarding.

Voice intents (Claude classification): play/pause/next/prev/volume_up/volume_down/play_calmer/play_upbeat.

## Build & deploy
Web: flutter build web --release && firebase deploy --only hosting --project aghieri-7a8ce
iOS (Mac): cd ios && pod install && cd .. && flutter build ios --release
Linux (Pi): flutter build linux --release

## Known patterns
- Hit testing: inverse spherical projection (_tapToLongitude)
- _MoonRng/_FocusRng: deterministic seeded RNG for consistent blob animation
- _moonLitPath(): right semicircle + elliptical terminator
- Night mirror: translate(2*cx, 0) + scale(-1, 1)
- Wedge math: reuse _moonLitPath() with custom terminator positions

## Never do
- Add red to UI
- Add gamification
- Store API keys in source or client env vars
- Restore typography selection screen
- Restore longitude stripes for tasks
- Play music pre-alarm outside fade-in window
- Let TTS overlap music at full volume (always duck)
- Use harsh transitions (default 200-500ms soft fades)
- Autoplay without user gesture (browser policy)

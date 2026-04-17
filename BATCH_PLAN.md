# Aghieri Batch Plan

## Batch 1: Onboarding fixes
In lib/features/onboarding/:
1. Welcome screen: Match "Get started" button font to "A guide through complexity. Not a judge of it." text above. Keep green pill background.
2. Name screen: Remove mic icon top-right entirely.
3. Typography selector: Delete from flow. Default profile to Adaptive mode on account creation. Update onboarding router.

## Batch 2: Terms of Service gate
1. Create lib/features/onboarding/terms_screen.dart as FIRST screen before welcome. Must check "I agree" to enable continue.
2. Store users/{uid}/profile.tos_accepted_at with server timestamp.
3. Settings → Terms of Service opens same content read-only.
4. Placeholder ToS copy (I'll write real text later).
5. Router guard: no tos_accepted_at → redirect to ToS on launch.

## Batch 3: Task creation improvements
In lib/features/tasks/:
1. Auto-step-generation on description:
   - After description entry, call Claude API (via api_keys_service) to break into steps
   - Show generated steps on next screen with edit/delete/reorder via AnimatedReorderableList
   - Skip if description empty
   - "Regenerate" button on steps screen
2. Multi-day support:
   - task_model.dart: add endDate (nullable String YYYY-MM-DD)
   - Bool get isMultiDay => endDate != null && endDate != dueDate
   - Date step: DateRangePicker with optional end date
   - Update Firestore writes/reads
   - Lazy migration: existing task with no endDate → endDate = dueDate on next read

## Batch 4: Moon wedge refactor (HIGHEST RISK)
Refactor lib/widgets/circular_display/circular_arc_display.dart. Replace stripes with wedges entirely.

1. Extract reusable: Path _crescentPath({required double startFrac, required double endFrac, required Size size}) — crescent between two terminators.
2. Per task (Today): startFrac/endFrac from scheduledTime/scheduledEndTime relative to wake/sleep window. Draw _crescentPath, fill task.color at 0.7 opacity.
3. Multi-day: 0.35 opacity, sin-wave pulse animation 4s period.
4. Active task: 0.85 opacity, layer lava lamp blob animation on wedge fill.
5. Hit test: Path.contains() → navigate /focus/{taskId}.
6. Night mode reset:
   - nightProgress = (now - sleepTime) / (wakeTime + 24h - sleepTime)
   - litFrac = nightProgress (0 at sleep, 1 at wake)
   - Task wedges hidden during night
7. Outer ring:
   - Default: white ambient blobs (existing)
   - Active task: ring color = active task color
   - Voice states: separate overlays via VoiceService callbacks
8. Tab-aware: Today = wake→sleep, Week = 7 days, Month = 30 days, Year = 365 days. Same math, different windows.

Preserve 3D sphere rendering, specular, atmospheric rim, ambient occlusion, _MoonRng.

Write a unit test verifying wedge startFrac/endFrac calculations against known wake/sleep windows BEFORE refactoring visuals.

## Batch 5: Focus screen overhaul
Refactor lib/features/focus/focus_screen.dart:
1. Title: Nunito 900 (add to pubspec.yaml fonts). Size fits 80% of inner circle width. Position at 80% height.
2. Title animation: Slice into vertical strips, apply scale + Y-offset via layered sine waves (3 frequencies, different phases). CustomPainter with slice rendering. Color = HSL complement of task.color, luminance-adjusted for AAA contrast.
3. Step display: One step at a time, centered below title at 40% height. AnimatedSwitcher with 400ms fade. Pull from task.steps. Track currentStepIndex in Firestore.
4. Advancement: Voice "next"/"done"/"ready" OR double-tap on focus circle. Last step complete → mark task complete, navigate back.
5. Voice toggle: Single tap mic → on/off. Filled when on, outlined when off.
6. Outer ring: +20px glow bleed via BackdropFilter with ImageFilter.blur(sigmaX: 12, sigmaY: 12) colored overlay. Glow color = HSL complement of task color. Keep lava lamp pattern.

## Batch 6: Wake-up routine
In lib/features/alarms/:
1. Create wakeup_routine.dart:
   - Triggers when alarm fires AND alarm.isWakeUp == true
   - Claude API prompt: "Generate calm 45-second morning briefing for {name}. Brief greeting, 1 short item per category from {interests}, end with first task: {firstTask}. Tone: gentle, encouraging, never urgent."
   - ElevenLabs Antonio voice
   - Hard-cap 60s (truncate at last sentence boundary before 55s)
   - 5+ interests → summarize across categories
2. alarm_model.dart: add bool isWakeUp (default false)
3. Alarm creation: "Wake-up alarm" toggle
4. Max 5 wake-up alarms in list
5. Wake-up UI: sun icon, warm amber accent

## Batch 7: Insights subpages
In lib/features/insights/:
1. Every metric card tappable → bottom sheet with:
   - Larger metric viz
   - AI description (Claude): "Explain in 2-3 sentences what {metric_name} tracks, what behaviors contributed to {value}, any trends. Calm, factual, non-judgmental. No motivational language."
   - Activity log table: timestamp, action, contributing metric
2. Your Pattern section: same treatment per pattern bubble
3. Cache descriptions at users/{uid}/insight_descriptions/{metric_id} with 24h TTL

## Batch 8: Voice state ring
1. Three states with distinct animations:
   - LISTENING green #7BC97B: flowing lava lamp, amplitude-reactive (AnalyserNode.getByteFrequencyData, avg bins 0-32)
   - THINKING amber #E8B86D: slow rotation, fixed amplitude
   - RESPONDING blue #6DA8E8: flowing, amplitude-reactive on TTS MediaStream
2. 30fps updates, EMA smoothed (alpha=0.3)
3. VoiceService callbacks: onListenStart→LISTENING, onProcessingStart→THINKING, onSpeakStart→RESPONDING, onIdle→default
4. 300ms cross-fade between states, no jump cuts

## Batch 9: Settings + integrations
In lib/features/settings/:
1. REMOVE Claude/ElevenLabs key input fields. Replace with "Connected services" status with green checkmarks.
2. Pre-provisioning infrastructure:
   - tools/provision_user.dart — admin script, takes UID, writes encrypted keys to admin_keys/{uid}
   - Firestore rules: reads locked to request.auth.uid == uid
   - lib/services/api_keys_service.dart — fetches, caches in memory only (never localStorage/IndexedDB)
3. Voice: Remove selection. Hardcode Antonio.
4. Latency reduction in voice_service.dart:
   - Stream Claude via SSE
   - Start ElevenLabs TTS on first sentence boundary (regex /[.!?]\s/), don't wait for full response
   - Cache common phrases ("got it", "okay", "next step", "all done") as pre-generated audio in Firebase Storage
   - Target: <800ms end-of-speech to start-of-TTS
5. WiFi setup section: QR code pairing for physical device, status only on web
6. Phone-as-login: device shows pairing QR → phone scans → Firebase auth → writes token to pairing_tokens/{token} → device polls every 2s
7. Google Calendar: bidirectional sync, last-edit wins
8. Notion: user picks database, pull/push tasks, completed → Notion pages

## Batch 10: Profile + analytics
1. Profile photo:
   - Tap avatar → file_picker → image_cropper
   - Upload users/{uid}/avatar.jpg in Firebase Storage
   - Display via cached_network_image, fallback to initials
2. Onboarding insights dashboard (lib/features/insights/onboarding_insights.dart):
   - Bar: tasks by category over time
   - Line: daily completion rate
   - Heatmap: time-of-day activity
   - fl_chart package
   - Colors: amber/green/blue/white only
   - Linked from Settings → "Your data"

## Batch 11: Music service
Create lib/services/music_service.dart:
1. Spotify Web API:
   - OAuth flow in Settings → "Connect Spotify"
   - Refresh token at users/{uid}/integrations/spotify
   - api_keys_service handles client_id/secret
   - spotify_sdk package for playback
2. Music intent classification in voice_service.dart Claude system prompt: play/pause/next/prev/volume_up/volume_down/play_calmer/play_upbeat
3. yt-dlp fallback:
   - Cloud Function endpoint returns audio stream URL
   - Web Audio API on web/iOS, native on Linux
4. Ambient controller:
   - Voice listening → duck to 15% over 200ms. Voice idle 1s → restore.
   - Focus start → auto-play focus playlist at 50%
   - 5 min pre-wake-up → fade in wake-up playlist 10%→60%
   - 30 min pre-sleep → low-energy tracks (energy<0.4, valence>0.4, tempo<100), fade to 0
5. Profile playlist prefs: wake-up, focus, break, wind-down (all optional, gentle defaults)
6. Now-playing card below moon clock: track + artist + simple controls. Auto-hide 30s after music stops.

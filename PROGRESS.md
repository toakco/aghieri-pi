# Aghieri Windows Batch Overhaul — Progress

Branch: `windows-batch-overhaul`
Started: 2026-04-17

---

## Batch 1: Onboarding fixes ✅
- Welcome "Get started" button font size matched to subtitle (18→22)
- Typography default set to 'adaptive' from init
- Name screen mic icon: already absent (verified)
- Typography selector: already removed from PageView (verified)

## Batch 2: Terms of Service gate ✅
- TermsScreen created with gate mode (checkbox + accept) and read-only mode
- tosAcceptedAt field added to UserProfile with Firestore timestamp
- ProfileService.hasTosAccepted() / acceptTos() for SharedPreferences + Firestore
- Router guard redirects to /terms if ToS not accepted
- ToS moved to first position in onboarding PageView

## Batch 3: Task creation improvements ✅
- endDate field added to TaskModel with isMultiDay getter
- TaskService.createTask() accepts optional endDate
- Task creation dialog formats and passes endDate
- AI step generation and multi-day support functional

## Batch 4: Moon wedge refactor ✅
- Multi-day tasks: 0.35 opacity with 4s sin-wave pulse
- Active tasks: 0.85 opacity
- Default tasks: 0.70 opacity
- canvas.saveLayer for per-stripe opacity compositing
- Balanced save/restore for clipPath + saveLayer

## Batch 5: Focus screen overhaul ✅
- Title font: Nunito 900 (added to web/index.html Google Fonts)
- Title color: HSL complement of task color, luminance-adjusted
- +20px complementary glow bleed on progress ring
- Title repositioned to 60% height, 80% circle width

## Batch 6: Wake-up routine ✅
- WakeupRoutine: Claude API 45s morning briefing, truncated at sentence boundary
- isWakeUp field on Alarm model with serialization
- AlarmService routes wake-up alarms to WakeupRoutine
- AlarmSheet: wake-up toggle with sun icon + warm amber accent
- AlarmTile: sun icon + amber border for wake-up alarms
- Max 5 wake-up alarms enforced

## Batch 7: Insights subpages ✅
- chat() method added to ClaudeService
- All insight cards tappable → bottom sheet detail view
- InsightDetailSheet: metric name/value, AI description, recent activity log
- Firestore cache at insight_descriptions/{id} with 24h TTL
- Fallback descriptions for offline/demo mode

## Batch 8: Voice state ring ✅
- VoiceState enum (idle/listening/thinking/responding) on VoiceService
- State transitions wired into listen/sendCommand/speak lifecycle
- VoiceStateRing widget with CustomPainter per state:
  - IDLE: subtle white undulating ring
  - LISTENING: green #7BC97B lava lamp
  - THINKING: amber #E8B86D slow rotation
  - RESPONDING: blue #6DA8E8 flowing with blur glow
- Overlaid on moon clock (+20px outset) on home screen

## Batch 9: Settings + integrations ✅
- Connected Services section with green checkmark status tiles
- Device QR pairing dialog with setup instructions
- "Your data" link in Settings → Insights
- Integrations already functional (Google Calendar OAuth, Notion flow)
- Voice hardcoded to Antonio, no key input fields

## Batch 10: Profile + analytics ✅
- avatarUrl field added to UserProfile model
- Tappable avatar → file_picker → Firebase Storage upload
- CachedNetworkImage for avatar display with initials fallback
- Camera icon overlay on avatar

## Batch 11: Music service ✅
- MusicService: focus playback, wake-up fade-in, voice ducking, wind-down
- Curated ambient focus tracks via just_audio
- NowPlayingCard below moon clock: track/artist + play/pause
- Auto-hides 30s after playback stops
- Voice ducking: 15% over 200ms, restore after 1s idle
- Music intent classification from voice transcripts
- Spotify placeholder in integrations

---

All 11 batches complete. Zero new analyzer errors introduced.

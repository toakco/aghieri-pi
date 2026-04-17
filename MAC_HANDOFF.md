# Aghieri — Mac Handoff

**For:** picking up the Aghieri Flutter project on a Mac (after Windows symposium deploy on 2026-04-17).
**Goal:** get macOS + iOS builds running, then flash the Pi 5 physical prototype.

All Windows-side work is already shipped at **https://aghieri-7a8ce.web.app** — the live web build is what's being demoed at the symposium. This doc is only for getting the native builds going.

---

## Part 0 — One-time Mac setup

If the Mac is fresh, install in this order. Skip any that are already installed.

```bash
# 1. Xcode — install from App Store (full Xcode, NOT just command line tools)
# Open it once after install, accept license, let it install components.
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch

# 2. Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. Flutter (via Homebrew is cleanest on Mac)
brew install --cask flutter
flutter doctor

# 4. CocoaPods (iOS deps manager)
sudo gem install cocoapods

# 5. Firebase CLI
curl -sL https://firebase.tools | bash
firebase login

# 6. Git (usually pre-installed)
git --version
```

Run `flutter doctor` and fix anything red before moving on. Xcode + CocoaPods + iOS simulator must all be green for iOS work.

---

## Part 1 — Pull the project

```bash
mkdir -p ~/Projects && cd ~/Projects
git clone https://github.com/toakco/aghieri.git
cd aghieri
git checkout windows-batch-overhaul
flutter pub get
```

**The branch is `windows-batch-overhaul`.** It is NOT merged to `main` yet — that's a post-symposium decision.

Confirm the branch is right:
```bash
git log --oneline -5
```
Top commit should be from 2026-04-17 (symposium day session work).

---

## Part 2 — macOS desktop build

macOS isn't scaffolded yet (Windows couldn't create it). Create it now:

```bash
flutter create --platforms=macos .
flutter pub get
```

Then build:
```bash
flutter build macos
open build/macos/Build/Products/Release/aghieri.app
```

First launch: macOS Gatekeeper will block it. Right-click the `.app` → **Open** → confirm. Or:
```bash
xattr -cr build/macos/Build/Products/Release/aghieri.app
```

**What to verify:** onboarding → home moon clock → `/device` route (navigate manually by hand if needed) → voice wake word "Aghieri" → Sign-in with Google + Apple.

Note: macOS microphone permission will prompt on first voice tap. Click **OK**.

---

## Part 3 — iOS build prep

Before the first iOS build, 3 things need to happen:

### 3a. Add the iOS Firebase config file

1. Go to https://console.firebase.google.com/project/aghieri-7a8ce/settings/general
2. Scroll to **Your apps** → find the **iOS** app (if it doesn't exist, click **Add app** → iOS, bundle ID: `com.toakco.aghieri`)
3. Click **GoogleService-Info.plist** → downloads the file
4. Drop that file into `ios/Runner/` (same folder as `Info.plist`)
5. Open `ios/Runner.xcworkspace` in Xcode → drag the plist into the `Runner` target in the left sidebar. **Check "Copy items if needed"** and make sure `Runner` target is checked.

### 3b. Add the Google Sign-In URL scheme

Open `ios/Runner/GoogleService-Info.plist` and find the value for key `REVERSED_CLIENT_ID`. It looks like `com.googleusercontent.apps.XXXXXXXXXX-xxxxxxxxxxxxxxxx`.

Then open `ios/Runner/Info.plist` and **before** the closing `</dict>` tag, paste:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>PASTE_REVERSED_CLIENT_ID_HERE</string>
    </array>
  </dict>
</array>
```

### 3c. Enable Sign in with Apple capability

1. Open `ios/Runner.xcworkspace` in Xcode
2. Click the **Runner** project in the left sidebar → select the **Runner** target
3. **Signing & Capabilities** tab
4. Set **Team** to your Apple Developer account
5. Click **+ Capability** → add **Sign in with Apple**
6. Click **+ Capability** → add **Push Notifications** (needed for alarm wake-up later)

Also under **Info** tab, confirm the `Bundle Identifier` matches what's in Firebase (`com.toakco.aghieri`).

### 3d. Install pods + build

```bash
cd ios
pod install --repo-update
cd ..
flutter build ios --release --no-codesign
# or to actually run on a device/simulator:
flutter run
```

**First real device run:** connect iPhone via USB → trust the computer → pick it from `flutter devices` → `flutter run -d <device-id>`. The app will fail to launch until you go to iPhone **Settings → General → VPN & Device Management → trust the developer profile**.

---

## Part 4 — Smoke test on iOS

Once the app launches:
1. Onboarding → name + typography mode
2. Home moon clock + voice ring animating
3. Tap voice ring → speak → TTS responds (ElevenLabs flash)
4. Tasks → create a task with end date → confirm multi-day pulse
5. Focus session → Nunito 900 title with complement glow
6. Settings → **Sign in** → Apple → confirm tile shows email after
7. Integrations → Spotify → should redirect to Spotify → back to app via deeplink

If Spotify redirect doesn't come back, the callback URL in Spotify dashboard may need an additional mobile deeplink entry. For now web-only OAuth is fine.

---

## Part 5 — Physical prototype (Raspberry Pi 5 + Waveshare 3.4" round)

Hardware needed:
- Raspberry Pi 5 (4GB or 8GB)
- Waveshare 3.4" round display (800×800, DSI ribbon)
- USB microphone (any cheap USB mic — the Pi has no built-in)
- Small USB speaker or 3.5mm speaker
- Power supply (official Pi 5 27W recommended)

### 5a. Flash Raspberry Pi OS

1. Download **Raspberry Pi Imager**: https://www.raspberrypi.com/software/
2. Pick **Raspberry Pi OS (64-bit) Bookworm with Desktop**
3. Click the ⚙️ gear icon → set hostname `aghieri`, enable SSH, set Wi-Fi, set user `pi` + password
4. Flash to microSD
5. Boot the Pi with the card in, wait 2 min for first boot

### 5b. Connect the Waveshare 3.4"

- Connect DSI ribbon cable between Pi and display (cable orientation matters — check Waveshare wiki)
- Follow Waveshare's overlay instructions: https://www.waveshare.com/wiki/3.4inch_DSI_LCD
- Usually edit `/boot/firmware/config.txt` to add their `dtoverlay=` line + display rotation
- Reboot

### 5c. Copy + run the kiosk script

From your Mac:
```bash
scp scripts/aghieri-pi-kiosk.sh pi@aghieri.local:~/aghieri-pi-kiosk.sh
ssh pi@aghieri.local
```

On the Pi:
```bash
sudo apt update
sudo apt install -y chromium-browser unclutter xdotool
chmod +x ~/aghieri-pi-kiosk.sh

# Autostart at login
mkdir -p ~/.config/lxsession/LXDE-pi
echo "@/home/pi/aghieri-pi-kiosk.sh" >> ~/.config/lxsession/LXDE-pi/autostart

# Test it now without rebooting
./aghieri-pi-kiosk.sh
```

Should boot straight into https://aghieri-7a8ce.web.app/device fullscreen with mic auto-granted. Tap the screen or say "Aghieri" — voice ring animates, TTS responds.

### 5d. Audio setup

```bash
# List audio devices
pactl list short sinks
pactl list short sources

# Set defaults (pick your USB mic + speaker from above)
pactl set-default-source alsa_input.usb-XXXXXX
pactl set-default-sink alsa_output.usb-XXXXXX
```

---

## Known issues / gotchas

- **Windows-style paths in Dart code:** none — the project uses relative paths throughout.
- **`cloud_functions` package on web:** there's a dart2js Int64 bug. The project works around it by calling Cloud Functions over raw HTTP with a Bearer token — see `lib/services/oauth_service.dart`. Keep using that pattern for any new functions.
- **Secrets on Cloud Functions:** already bound via Firebase Secret Manager. `firebase functions:secrets:access ANTHROPIC_KEY` to inspect, or `firebase functions:secrets:set KEY_NAME` to rotate. Secret names must be UPPER_SNAKE_CASE.
- **Minimum instances:** `voiceCommand` and `textToSpeech` both run with `minInstances: 1` for latency. ~$5-8/mo cost. Don't remove without a reason.
- **Apple Sign-In on web:** works only on Safari or when served over HTTPS with a registered Services ID. For local dev, Apple Sign-In button will error — that's expected.

---

## Quick reference — project structure

| Path | Purpose |
|---|---|
| `lib/app.dart` | Router (GoRouter) — all routes including `/device`, `/sign-in`, OAuth callbacks |
| `lib/services/voice_service.dart` | STT + wake word + ElevenLabs TTS |
| `lib/services/auth_service.dart` | Firebase anon → Google/Apple linking |
| `lib/services/oauth_service.dart` | Spotify + Notion OAuth via Cloud Functions |
| `lib/features/device/` | Circular voice-first UI for the Pi prototype |
| `functions/index.js` | All Cloud Functions (voiceCommand, textToSpeech, OAuth) |
| `scripts/aghieri-pi-kiosk.sh` | Pi 5 Chromium kiosk launcher |

---

## If something is wrong

1. `flutter clean && flutter pub get && cd ios && pod install --repo-update && cd ..`
2. Check `flutter doctor` — all green except "connected device" is OK
3. Firebase CLI authed: `firebase projects:list` should show `aghieri-7a8ce`
4. Hosting still live: `curl -I https://aghieri-7a8ce.web.app` → 200
5. Ping Windows-side handoff: see `SESSION_HANDOFF.md` for what shipped on 2026-04-17

#!/usr/bin/env bash
# Aghieri — Raspberry Pi 5 kiosk launcher for the round 800x800 device build.
#
# Targets a Waveshare 3.4" round DSI display (800x800) running Raspberry Pi OS
# Bookworm. Boots Chromium straight into the /device route in fullscreen kiosk
# mode, with mic + autoplay permissions pre-granted so voice works without a
# user-gesture prompt. Drop this in /home/pi/ and reference it from autostart.
#
# Install (one-time):
#   sudo apt update && sudo apt install -y chromium-browser unclutter xdotool
#   chmod +x /home/pi/aghieri-pi-kiosk.sh
#
# Autostart (LXDE/Wayfire):
#   echo "@/home/pi/aghieri-pi-kiosk.sh" >> ~/.config/lxsession/LXDE-pi/autostart
#   # or for wayfire add an [autostart] entry pointing at this script.

set -euo pipefail

URL="${AGHIERI_URL:-https://aghieri-7a8ce.web.app/device}"
PROFILE_DIR="${HOME}/.aghieri-kiosk-profile"
LOG_DIR="${HOME}/.aghieri-kiosk-logs"

mkdir -p "$PROFILE_DIR" "$LOG_DIR"

# Disable screen blanking + cursor while kiosk is running.
xset -dpms       || true
xset s off       || true
xset s noblank   || true
unclutter -idle 0.1 -root &

# Pre-seed Preferences so Chromium auto-grants mic to the deployed origin.
PREFS="${PROFILE_DIR}/Default/Preferences"
mkdir -p "$(dirname "$PREFS")"
if [ ! -f "$PREFS" ]; then
  cat > "$PREFS" <<'JSON'
{
  "profile": {
    "content_settings": {
      "exceptions": {
        "media_stream_mic": {
          "https://aghieri-7a8ce.web.app:443,*": {
            "setting": 1
          }
        }
      }
    },
    "default_content_setting_values": {
      "media_stream_mic": 1,
      "notifications": 2
    }
  }
}
JSON
fi

# Launch Chromium in kiosk mode with voice-friendly flags.
# --use-fake-ui-for-media-stream: skip the mic permission prompt
# --autoplay-policy=no-user-gesture-required: TTS audio plays without a tap
# --noerrdialogs / --disable-session-crashed-bubble: clean recovery on power-cut
exec chromium-browser \
  --kiosk \
  --start-fullscreen \
  --window-size=800,800 \
  --window-position=0,0 \
  --user-data-dir="$PROFILE_DIR" \
  --noerrdialogs \
  --disable-infobars \
  --disable-translate \
  --disable-features=TranslateUI,Translate \
  --disable-pinch \
  --overscroll-history-navigation=0 \
  --disable-session-crashed-bubble \
  --check-for-update-interval=31536000 \
  --use-fake-ui-for-media-stream \
  --autoplay-policy=no-user-gesture-required \
  --enable-features=OverlayScrollbar \
  --hide-scrollbars \
  "$URL" \
  >> "${LOG_DIR}/chromium.log" 2>&1

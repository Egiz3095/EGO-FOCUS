#!/bin/bash
# Launches the simulator build with demo data and captures every main screen in light and dark mode.
set -euo pipefail
UDID="$1"; APP="$2"; OUT="$3"
BUNDLE=com.egofocus.tasks
# Render the demo at ~10:00 local time regardless of when CI runs (TZ is passed to the app).
UTC_HOUR=$(date -u +%H); OFFSET=$(( (10 - 10#$UTC_HOUR + 24) % 24 )); [ $OFFSET -gt 14 ] && OFFSET=$((OFFSET-24))
if [ $OFFSET -ge 0 ]; then export SIMCTL_CHILD_TZ="Etc/GMT-$OFFSET"; else export SIMCTL_CHILD_TZ="Etc/GMT+$((-OFFSET))"; fi
echo "screenshot timezone: $SIMCTL_CHILD_TZ"
mkdir -p "$OUT"
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true
shoot() { # appearance name extra-args...
  local appearance="$1" name="$2"; shift 2
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -uiTesting -resetStore -demoData -egofocus_appearance "$appearance" "$@" >/dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "$OUT/${appearance}-${name}.png" >/dev/null
  echo "captured ${appearance}-${name}"
}
for appearance in light dark; do
  xcrun simctl ui "$UDID" appearance "$appearance" || true
  shoot "$appearance" 1-home -tab home
  shoot "$appearance" 2-calendar -tab calendar
  shoot "$appearance" 3-reports -tab reports
  shoot "$appearance" 4-settings -tab settings
  shoot "$appearance" 5-assistant -tab home -openAssistant
  shoot "$appearance" 6-editor -tab home -openEditor
done
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true

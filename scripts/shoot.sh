#!/usr/bin/env bash
# Capture screenshots of the built site for visual review (Q16.3).
# Builds, serves public/ on a throwaway port, drives headless Chromium
# under Xvfb, writes PNGs to notes/screenshots/.
#
# Usage:  bash scripts/shoot.sh [path ...]      (default: / /projects/ /writing/)
set -euo pipefail
cd "$(dirname "$0")/.."

# Locate a real Chromium/Chrome (the distro /usr/bin/chromium-browser may
# be a broken stub; Playwright's bundled binary is a reliable fallback).
CHROME="${CHROME:-}"
if [ -z "$CHROME" ]; then
  for c in \
    "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux64/chrome \
    "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux/chrome \
    /usr/bin/google-chrome /usr/bin/chromium; do
    [ -x "$c" ] && { CHROME="$c"; break; }
  done
fi
[ -x "$CHROME" ] || { echo "No working Chrome/Chromium found; set CHROME=..." >&2; exit 1; }

PORT="${PORT:-8237}"
OUT=notes/screenshots
mkdir -p "$OUT"

make publish >/dev/null
( cd public && python3 -m http.server "$PORT" >/dev/null 2>&1 ) &
SV=$!
trap 'kill $SV 2>/dev/null || true' EXIT
sleep 2

paths=("$@"); [ ${#paths[@]} -eq 0 ] && paths=(/ /projects/ /writing/)
i=1
for p in "${paths[@]}"; do
  label=$(echo "$p" | tr '/' '-' | sed 's/^-//; s/-$//')
  [ -z "$label" ] && label=landing
  name=$(printf '%02d-%s.png' "$i" "$label")
  xvfb-run -a "$CHROME" --headless=new --no-sandbox --disable-gpu \
    --hide-scrollbars --force-color-profile=srgb --window-size=1100,800 \
    --virtual-time-budget=4000 \
    --screenshot="$OUT/$name" "http://localhost:$PORT$p" >/dev/null 2>&1
  echo "  $p -> $OUT/$name"
  i=$((i+1))
done

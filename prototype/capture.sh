#!/usr/bin/env bash
# Render the prototype groups to PNG with headless Chrome (1500x2200 @2x).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
OUT="$ROOT/shots"
mkdir -p "$OUT"

python3 "$ROOT/build.py"

for theme in light dark; do
  suffix=""
  [ "$theme" = "dark" ] && suffix="-dark"
  for group in records doulist plan report reportstyles settings decisions; do
    height=2200
    [ "$group" = "records" ] && height=4400
    [ "$group" = "settings" ] && height=3000
    [ "$group" = "report" ] && height=1160
    [ "$group" = "reportstyles" ] && height=1220
    [ "$group" = "doulist" ] && height=1200
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
      --window-size=1500,$height --force-device-scale-factor=2 \
      --screenshot="$OUT/$group$suffix.png" \
      "file://$ROOT/index.html?only=$group&theme=$theme" >/dev/null 2>&1
    echo "wrote shots/$group$suffix.png"
  done
done

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1500,2200 --force-device-scale-factor=2 \
  --screenshot="$OUT/board.png" "file://$ROOT/index.html" >/dev/null 2>&1
echo "wrote shots/board.png"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1500,2200 --force-device-scale-factor=2 \
  --screenshot="$OUT/board-dark.png" "file://$ROOT/index.html?theme=dark" >/dev/null 2>&1
echo "wrote shots/board-dark.png"

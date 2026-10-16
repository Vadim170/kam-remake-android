#!/bin/bash
# Copies KaM Remake game data to the phone (app-specific external storage, no permissions needed)
set -euo pipefail
ANDROID_DIR="$(cd "$(dirname "$0")" && pwd)"
TC="${KAM_TOOLCHAIN:-$(cd "$ANDROID_DIR/.." && pwd)/toolchain}"
SRC="${KAM_DATA:-$TC/kamres/app}"
SERIAL="${ANDROID_SERIAL:?set ANDROID_SERIAL}"
DST=/sdcard/Android/data/org.kamremake.android/files
adb -s "$SERIAL" shell mkdir -p "$DST"
for d in data Campaigns Maps MapsMP Music Sounds Tutorials; do
  echo "pushing $d"
  adb -s "$SERIAL" push --sync "$SRC/$d" "$DST/" | tail -1
done

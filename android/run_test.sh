#!/bin/bash
# Build (unless NOBUILD=1), install, launch and collect engine logs; symbolizes KaMCrash stacks
set -uo pipefail
ANDROID_DIR="$(cd "$(dirname "$0")" && pwd)"
export ANDROID_SERIAL="${ANDROID_SERIAL:-R58R74Z20BJ}"
B=$HOME/Library/Android/sdk/ndk/29.0.13599879/toolchains/llvm/prebuilt/darwin-x86_64/bin
if [ "${NOBUILD:-0}" != 1 ]; then
  "$ANDROID_DIR/build_apk.sh" > "$ANDROID_DIR/build/apk.log" 2>&1 || { grep -E "Error|error:|FAIL" "$ANDROID_DIR/build/apk.log" | head -20; exit 1; }
  adb install -r "$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk" | tail -1
fi
adb shell am force-stop org.kamremake.android
adb logcat -c
adb shell am start -n org.kamremake.android/.KaMActivity > /dev/null
sleep "${WAIT:-20}"
# TAPS="x,y x,y ..." taps (phone pixels) with TAP_DELAY seconds between them, then AFTER seconds
for t in ${TAPS:-}; do adb shell input tap ${t%,*} ${t#*,}; sleep "${TAP_DELAY:-3}"; done
[ -n "${TAPS:-}" ] && sleep "${AFTER:-10}"
adb exec-out screencap -p > "$ANDROID_DIR/build/shot.png" && sips -Z 900 "$ANDROID_DIR/build/shot.png" --out "$ANDROID_DIR/build/shot_s.png" > /dev/null
adb logcat -d > "$ANDROID_DIR/build/logcat.txt"
grep -E " (KaM|KaMHost|KaMBass|KaMCrash|KaMStdout)\s*:" "$ANDROID_DIR/build/logcat.txt" | sed -E 's/^.{19}//' | tail -${LINES_SHOWN:-40}
grep "KaMCrash" "$ANDROID_DIR/build/logcat.txt" | grep -oE "(libkamcore|libGL|libbass|libopenal).so\+0x[0-9a-f]+" | awk '!s[$0]++' | while IFS=+ read lib a; do
  "$B/llvm-symbolizer" --obj="$ANDROID_DIR/app/src/main/jniLibs/arm64-v8a/$lib" $(printf '0x%x' $((a - 4))) | head -2 | tr '\n' ' ' | sed "s|$HOME/Downloads/Knights.and.Merchants.v1.60/Knights.and.Merchants.v1.60/||g"; echo
done
echo "alive pid: $(adb shell pidof org.kamremake.android)"

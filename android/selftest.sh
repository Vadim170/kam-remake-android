#!/bin/bash
# Runs the in-app content smoke test on a connected device and prints the results.
# Usage: ANDROID_SERIAL=<id> ./selftest.sh [campaigns|campaigns-all|maps|all]
set -uo pipefail
ANDROID_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-campaigns}"
B=$HOME/Library/Android/sdk/ndk/29.0.13599879/toolchains/llvm/prebuilt/darwin-x86_64/bin
LOG="$ANDROID_DIR/build/selftest_logcat.txt"
mkdir -p "$ANDROID_DIR/build"
adb shell am force-stop org.kamremake.android
adb logcat -c
adb shell am start -n org.kamremake.android/.KaMActivity --es kam_selftest "$MODE" > /dev/null
echo "Self test '$MODE' started"
# Wait until the test reports DONE or the app process disappears
sleep 10
while true; do
  sleep 5
  adb logcat -d > "$LOG"
  grep -q "KAMTEST DONE" "$LOG" && break
  if [ -z "$(adb shell pidof org.kamremake.android)" ]; then echo "!!! app process died"; break; fi
  last=$(grep -oE "KAMTEST (START|OK|FAIL)[^[:cntrl:]]*" "$LOG" | tail -1); [ -n "$last" ] && echo "  ... $last"
done
grep -oE "KAMTEST (OK|FAIL|DONE|items|BEGIN)[^[:cntrl:]]*" "$LOG"
if grep -q "KaMCrash: signal" "$LOG"; then
  echo "!!! CRASH during: $(grep -oE 'KAMTEST START [^[:cntrl:]]*' "$LOG" | tail -1)"
  grep "KaMCrash" "$LOG" | grep -oE "libkamcore.so\+0x[0-9a-f]+" | awk '!s[$0]++' | head -12 | while IFS=+ read lib a; do
    "$B/llvm-symbolizer" --obj="$ANDROID_DIR/app/src/main/jniLibs/arm64-v8a/$lib" $(printf '0x%x' $((a - 4))) | head -1
  done
  exit 1
fi
grep -q "KAMTEST DONE passed=[0-9]* failed=0" "$LOG"

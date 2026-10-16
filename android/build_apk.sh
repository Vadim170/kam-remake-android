#!/bin/bash
# Full build: native audio shim, Pascal engine, native libs collection, APK
set -euo pipefail
ANDROID_DIR="$(cd "$(dirname "$0")" && pwd)"
TC="${KAM_TOOLCHAIN:-$(cd "$ANDROID_DIR/.." && pwd)/toolchain}"
JNI="$ANDROID_DIR/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$JNI"
"$ANDROID_DIR/native/build_bass.sh"
# Always build the engine from scratch: incremental FPC 3.2.2 builds hit "Internal error 200611031" with generics
rm -rf "$ANDROID_DIR/build/units_main"
"$ANDROID_DIR/build_native.sh" > "$ANDROID_DIR/build/last.log" 2>&1 || { grep -E 'Error|Fatal' "$ANDROID_DIR/build/last.log" | head -20; exit 1; }
for f in libGL.so; do cp "$TC/gl4es/lib/$f" "$JNI/"; done
for f in libopenal.so libogg.so libvorbis.so libvorbisfile.so libbass.so; do cp "$TC/android-libs/lib/$f" "$JNI/"; done
rm -f "$JNI"/*.res "$JNI"/*.o
# KAM_BUNDLE_DATA=1: include game data in the APK (links, no copies)
GRADLE_ARGS=()
if [ "${KAM_BUNDLE_DATA:-0}" = 1 ]; then
  SRC="${KAM_DATA:-$TC/kamres/app}"
  rm -rf "$ANDROID_DIR/build/bundle"; mkdir -p "$ANDROID_DIR/build/bundle/kamdata"
  for d in data Campaigns Maps MapsMP Music Sounds Tutorials; do ln -s "$SRC/$d" "$ANDROID_DIR/build/bundle/kamdata/$d"; done
  # File list with sizes for the extractor
  (cd "$SRC" && find data Campaigns Maps MapsMP Music Sounds Tutorials -type f -exec stat -f '%z %N' {} +) > "$ANDROID_DIR/build/bundle/kamdata.lst"
  GRADLE_ARGS+=(-Pkam.bundleData=true)
fi
cd "$ANDROID_DIR"
# Gradle needs the SDK location
[ -f local.properties ] || echo "sdk.dir=${ANDROID_HOME:-$HOME/Library/Android/sdk}" > local.properties
"${GRADLE:-./gradlew}" -q assemble${KAM_BUILD_TYPE:-Debug} ${GRADLE_ARGS[@]+"${GRADLE_ARGS[@]}"}
ls -la "$ANDROID_DIR"/app/build/outputs/apk/*/*.apk

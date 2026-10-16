#!/bin/bash
# Builds libbass.so (BASS API subset on OpenAL) for Android arm64
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TC="${KAM_TOOLCHAIN:-$(cd "$DIR/../.." && pwd)/toolchain}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk/29.0.13599879}"
LIBS="$TC/android-libs"
"$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang" --target=aarch64-linux-android26 -O2 -fPIC -shared -fvisibility=hidden \
  -Wall -Wno-unused-function \
  -I"$TC/minimp3" -I"$LIBS/include" \
  -o "$LIBS/lib/libbass.so" "$DIR/bass_android.c" \
  -L"$LIBS/lib" -lopenal -lvorbisfile -lvorbis -logg -llog -lm \
  -Wl,-soname,libbass.so -Wl,-z,max-page-size=16384
echo "built $LIBS/lib/libbass.so"

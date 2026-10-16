#!/bin/bash
# Builds the KaM Remake engine as a native arm64 Android library (libkamcore.so)
set -euo pipefail
ANDROID_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ANDROID_DIR/.." && pwd)"
TC="${KAM_TOOLCHAIN:-$REPO/toolchain}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk/29.0.13599879}"
export KAM_NDK="$NDK"
FPC_SRC="$TC/fpc-3.2.2"
LAZ="$TC/lazarus"
UNITS="${KAM_UNITS:-$ANDROID_DIR/build/units_main}"
OUT="${KAM_OUT:-$ANDROID_DIR/app/src/main/jniLibs/arm64-v8a}"
mkdir -p "$UNITS" "$OUT"
export PATH="$TC/bin:$PATH"

# Multiplayer UI is hidden unless KAM_MULTIPLAYER=1
DEFS=()
[ "${KAM_MULTIPLAYER:-0}" = 1 ] || DEFS+=(-dNO_MULTIPLAYER_UI)

FU=()
FU+=(-Fu"$ANDROID_DIR/pascal/shims" -Fi"$ANDROID_DIR/pascal/shims")
for d in $(cd "$REPO/src" && find . -type d \
    -not -path './forms*' -not -path './ext/Virtual-TreeView*' -not -path './ext/BGRABitmap*' \
    -not -path './ext/Overbyte*' -not -path './ext/LazarusOpenGL*' -not -path './ext/pascalscript_submodule*' \
    -not -path './unused*' | sort); do
  FU+=(-Fu"$REPO/src/$d" -Fi"$REPO/src/$d")
done
FU+=(-Fu"$REPO/src/ext/pascalscript_submodule/Source" -Fi"$REPO/src/ext/pascalscript_submodule/Source")
FU+=(-Fu"$ANDROID_DIR/build/lazutils")
for p in rtl-objpas rtl-generics rtl-extra fcl-image fcl-base fcl-json fcl-xml fcl-process paszlib hash regexpr fcl-net rtl-unicode pthreads fcl-registry; do
  FU+=(-Fu"$FPC_SRC/packages/$p/units/aarch64-android")
done

"$FPC_SRC/compiler/ppcrossa64" -Tandroid -Paarch64 -Cg -Xd -MDelphi -Sh -Sa \
  -dANDROID_PORT -dDBG_SKIP_SECURE_AUTH \
  -XPaarch64-linux-android- \
  -Fu"$FPC_SRC/rtl/units/aarch64-android" \
  -Fi"$REPO" "${FU[@]}" \
  -FU"$UNITS" -FE"$OUT" -o"$OUT/libkamcore.so" \
  -Fl"$NDK/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/26" \
  -Fl"$TC/android-libs/lib" \
  -k-z -kmax-page-size=16384 \
  -O2 -g -gl -vewn -vm5023,5024,5025,5026,5027,5028,5057,5058,5059,5060,5089,5090,5091,5092,5093,6058,3123,3124,4055,4056,4079,4080,4081,4082,5036,5037,4035,4105,4104 \
  ${DEFS[@]+"${DEFS[@]}"} ${KAM_FPC_FLAGS:-} "$@" "$ANDROID_DIR/pascal/kamcore.lpr"

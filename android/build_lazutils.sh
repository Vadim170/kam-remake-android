#!/bin/bash
# Precompiles the LazUtils units used by the engine for aarch64-android
set -euo pipefail
ANDROID_DIR="$(cd "$(dirname "$0")" && pwd)"
TC="${KAM_TOOLCHAIN:-$(cd "$ANDROID_DIR/.." && pwd)/toolchain}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk/29.0.13599879}"
export KAM_NDK="$NDK"
FPC_SRC="$TC/fpc-3.2.2"
LAZ="$TC/lazarus/components/lazutils"
OUT="$ANDROID_DIR/build/lazutils"
mkdir -p "$OUT"
export PATH="$TC/bin:$PATH"
FU=()
for p in rtl-objpas rtl-generics fcl-base fcl-process rtl-unicode fcl-xml fcl-json fcl-registry; do
  FU+=(-Fu"$FPC_SRC/packages/$p/units/aarch64-android")
done
cat > "$OUT/lazutils_all.pas" <<'PAS'
unit lazutils_all;
interface
uses LazUTF8, LConvEncoding, LazFileUtils, FileUtil, Laz2_DOM, Laz2_XMLRead, Laz2_XMLWrite, UTF8Process;
implementation
end.
PAS
"$FPC_SRC/compiler/ppcrossa64" -Tandroid -Paarch64 -Cg -CX -MObjFPC -Scghi -O2 -g -gl \
  -Fu"$FPC_SRC/rtl/units/aarch64-android" "${FU[@]}" -Fu"$LAZ" -Fi"$LAZ" -FU"$OUT" "$OUT/lazutils_all.pas"

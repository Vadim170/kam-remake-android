#!/bin/bash
# Downloads and builds everything needed to build the Android port (macOS arm64/x86_64 host).
# Result goes to $KAM_TOOLCHAIN (default: <repo>/toolchain, ignored by git).
#
# Prerequisites:
#   - Free Pascal 3.2.2 host compiler (brew install fpc)
#   - Android SDK with NDK 29.0.13599879, CMake (SDK cmake package) and platform 36
#   - JDK 17+, python3, git, curl
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TC="${KAM_TOOLCHAIN:-$REPO/toolchain}"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
NDK="${ANDROID_NDK_HOME:-$SDK/ndk/29.0.13599879}"
CM_BIN="$(ls -d "$SDK"/cmake/*/bin | sort -V | tail -1)"
HOST_TAG=darwin-x86_64 # NDK ships universal binaries under this name on macOS
PATCHES="$HERE/patches"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

FPC_TAG=release_3_2_2
LAZARUS_TAG=lazarus_3_0
GL4ES_COMMIT=a025615bc79ac43ec911dced8fe5b8eb45a0b72d
MINIMP3_COMMIT=ea99364f61c14656440e8d77e9c233ccf3124633
OPENAL_TAG=1.24.3
OGG_TAG=v1.3.5
VORBIS_TAG=v1.3.7

command -v fpc >/dev/null || { echo "Host Free Pascal (fpc 3.2.2) is required: brew install fpc"; exit 1; }
[ -d "$NDK" ] || { echo "Android NDK not found at $NDK"; exit 1; }
mkdir -p "$TC" "$TC/bin"
echo "Toolchain dir: $TC"

# --- Binutils for FPC: NDK lld/llvm-ar and clang as assembler ---
ln -sf "$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/ld.lld" "$TC/bin/aarch64-linux-android-ld"
ln -sf "$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/llvm-ar" "$TC/bin/aarch64-linux-android-ar"
cat > "$TC/bin/aarch64-linux-android-as" <<'PY'
#!/usr/bin/env python3
# GNU as compatible front-end for FPC: assembles with the NDK clang
import os, sys
ndk = os.environ['KAM_NDK']
cmd = [ndk + '/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang', '--target=aarch64-linux-android26', '-c', '-x', 'assembler']
a = iter(sys.argv[1:])
for x in a:
    if x == '--defsym': cmd.append('-Wa,-defsym,' + next(a))
    elif x.startswith('-march='): cmd.append(x)
    elif x == '--noexecstack': pass
    else: cmd.append(x)
os.execv(cmd[0], cmd)
PY
chmod +x "$TC/bin/aarch64-linux-android-as"
export KAM_NDK="$NDK"
export PATH="$TC/bin:$PATH"
# macOS: the host linker needs the SDK path to find libSystem when FPC builds its own compilers
command -v xcrun >/dev/null && export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"

# --- Free Pascal 3.2.2 cross compiler + RTL + packages for aarch64-android ---
if [ ! -x "$TC/fpc-3.2.2/compiler/ppcrossa64" ] || [ ! -d "$TC/fpc-3.2.2/rtl/units/aarch64-android" ]; then
  echo "== FPC $FPC_TAG"
  rm -rf "$TC/fpc-3.2.2"
  curl -fsSL "https://gitlab.com/freepascal.org/fpc/source/-/archive/$FPC_TAG/source-$FPC_TAG.tar.gz" | tar -xz -C "$TC"
  mv "$TC/source-$FPC_TAG" "$TC/fpc-3.2.2"
  # NDK ld.lld can't handle the stock linker script fragment
  patch -d "$TC/fpc-3.2.2" -p1 < "$PATCHES/fpc-3.2.2-android-lld.patch"
  make -C "$TC/fpc-3.2.2" -j"$JOBS" crossall OS_TARGET=android CPU_TARGET=aarch64 \
    BINUTILSPREFIX=aarch64-linux-android- CROSSOPT="-Cg" OPT="${SDKROOT:+-Fl$SDKROOT/usr/lib}" PP="$(command -v fpc)" > "$TC/fpc-build.log" 2>&1 \
    || { tail -30 "$TC/fpc-build.log"; exit 1; }
fi

# --- LazUtils sources (Lazarus 3.0) ---
if [ ! -d "$TC/lazarus/components/lazutils" ]; then
  echo "== Lazarus $LAZARUS_TAG (LazUtils)"
  rm -rf "$TC/lazarus"
  git clone -q --depth 1 --branch "$LAZARUS_TAG" https://gitlab.com/freepascal.org/lazarus/lazarus.git "$TC/lazarus"
fi

# --- gl4es: desktop OpenGL on GLES2 ---
if [ ! -f "$TC/gl4es/lib/libGL.so" ]; then
  echo "== gl4es"
  rm -rf "$TC/gl4es" "$TC/build-gl4es"
  git clone -q https://github.com/ptitSeb/gl4es.git "$TC/gl4es"
  git -C "$TC/gl4es" checkout -q "$GL4ES_COMMIT"
  git -C "$TC/gl4es" apply "$PATCHES/gl4es-android-host-context.patch"
  "$CM_BIN/cmake" -Wno-dev -S "$TC/gl4es" -B "$TC/build-gl4es" -G Ninja -DCMAKE_MAKE_PROGRAM="$CM_BIN/ninja" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=26 \
    -DANDROID=1 -DNOX11=ON -DUSE_ANDROID_LOG=ON -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" > /dev/null
  "$CM_BIN/ninja" -C "$TC/build-gl4es" > /dev/null
fi

# --- Audio: openal-soft, libogg, libvorbis, minimp3 ---
clone_tag() { [ -d "$TC/$2" ] || git clone -q --depth 1 --branch "$3" "$1" "$TC/$2"; }
clone_tag https://github.com/kcat/openal-soft.git openal-soft "$OPENAL_TAG"
clone_tag https://github.com/xiph/ogg.git libogg "$OGG_TAG"
clone_tag https://github.com/xiph/vorbis.git libvorbis "$VORBIS_TAG"
if [ ! -d "$TC/minimp3" ]; then
  git clone -q https://github.com/lieff/minimp3.git "$TC/minimp3"
  git -C "$TC/minimp3" checkout -q "$MINIMP3_COMMIT"
fi
if [ ! -f "$TC/android-libs/lib/libopenal.so" ]; then
  echo "== audio libraries"
  PREFIX="$TC/android-libs"
  COMMON=(-Wno-dev -G Ninja -DCMAKE_MAKE_PROGRAM="$CM_BIN/ninja" -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=26 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX"
    -DCMAKE_FIND_ROOT_PATH="$PREFIX" -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" -DCMAKE_POLICY_VERSION_MINIMUM=3.5)
  b() { local src=$1; shift; rm -rf "$TC/build-$src"; "$CM_BIN/cmake" -S "$TC/$src" -B "$TC/build-$src" "${COMMON[@]}" "$@" > /dev/null; "$CM_BIN/ninja" -C "$TC/build-$src" install > /dev/null; rm -rf "$TC/build-$src"; }
  b libogg -DBUILD_SHARED_LIBS=ON -DINSTALL_DOCS=OFF -DBUILD_TESTING=OFF
  b libvorbis -DBUILD_SHARED_LIBS=ON -DOGG_INCLUDE_DIR="$PREFIX/include" -DOGG_LIBRARY="$PREFIX/lib/libogg.so"
  b openal-soft -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF -DALSOFT_INSTALL_CONFIG=OFF \
    -DALSOFT_INSTALL_HRTF_DATA=OFF -DALSOFT_INSTALL_AMBDEC_PRESETS=OFF -DALSOFT_BACKEND_OPENSL=ON -DALSOFT_REQUIRE_OPENSL=ON -DLIBTYPE=SHARED
fi

# --- PascalScript: aarch64 support for script event handlers (submodule patch) ---
PS="$REPO/src/ext/pascalscript_submodule"
[ -f "$PS/Source/uPSRuntime.pas" ] || git -C "$REPO" submodule update --init src/ext/pascalscript_submodule
if [ ! -f "$PS/Source/aarch64methods.inc" ]; then
  echo "== PascalScript aarch64 patch"
  git -C "$PS" apply "$PATCHES/pascalscript-aarch64.patch"
fi

# --- LazUtils precompiled for the target ---
KAM_TOOLCHAIN="$TC" "$REPO/android/build_lazutils.sh" > "$TC/lazutils-build.log" 2>&1 || { tail -20 "$TC/lazutils-build.log"; exit 1; }

echo "Toolchain ready in $TC"

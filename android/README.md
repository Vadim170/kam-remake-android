# KaM Remake for Android (native arm64 port)

A native Android build of [KaM Remake](https://github.com/reyandme/kam_remake) r16397 — the open source
engine for *Knights and Merchants*. The original Pascal engine is compiled for arm64 with Free Pascal
(no emulation, no Wine); a small Java/C host provides the window, OpenGL context, touch input and video.

The game itself looks and plays exactly like the PC version. Phone specific changes only:
screen proportions and rotation, interface scale (up to 2x), touch controls, scrollable left panel,
soft keyboard, app lifecycle (saving settings when the app goes to background).

**This repository contains no game data.** You need your own copy of Knights and Merchants and the
KaM Remake installer from [kamremake.com](https://www.kamremake.com/download/) (it requires the original game).

## Controls

| Gesture | Action |
|---|---|
| tap | left click |
| long press | right click; keep holding and move to choose troop direction |
| two-finger tap | right click |
| drag on the map | scroll the map (while a build/editor tool is active: draw with it) |
| pinch / two-finger drag | zoom / scroll |
| vertical drag on the left panel | scroll the panel when it does not fit the screen |
| Back button | Esc (skip video, close panel) |
| three-finger tap | interface scale (0.5–2.0) |

USB/Bluetooth mouse and keyboard work as on PC.

## Building

Host: macOS (Apple Silicon or Intel). Requirements:

- Free Pascal 3.2.2 host compiler: `brew install fpc`
- `brew install innoextract` (to unpack the KaM Remake installer)
- Android SDK with NDK `29.0.13599879`, CMake package and platform 36; JDK 17+; python3, git, curl

```sh
git clone --recursive <this repo> kam-remake-android
cd kam-remake-android

# 1. Toolchain: FPC cross compiler for aarch64-android, LazUtils, gl4es, OpenAL, ogg/vorbis, minimp3 (~20 min)
android/toolchain/setup_toolchain.sh

# 2. Game data from your KaM Remake installer (not distributed here)
android/toolchain/extract_data.sh ~/Downloads/kam_remake_installer.exe

# 3. APK
cd android
./build_apk.sh                                      # debug APK without data (~30 MB)
KAM_BUILD_TYPE=Release KAM_BUNDLE_DATA=1 ./build_apk.sh   # release APK with the game data inside (~0.85 GB)
```

The APK is in `android/app/build/outputs/apk/<debug|release>/`.

- **APK with data** (`KAM_BUNDLE_DATA=1`): install and start, it unpacks the data once (~1 minute).
- **APK without data**: copy `data, Campaigns, Maps, MapsMP, Music, Sounds, Tutorials` from the KaM Remake
  folder to `/sdcard/Android/data/org.kamremake.android/files/` (`ANDROID_SERIAL=<device> ./push_data.sh`).

Options: `KAM_MULTIPLAYER=1` shows the Multiplayer menu (hidden by default, not finished on Android);
`KAM_FPC_FLAGS=-dANDROID_GLDEBUG` / `-dANDROID_MEMDEBUG` add GL and memory diagnostics.
`./run_test.sh` installs, runs and collects logcat with symbolized crash stacks.

## How it works

- `pascal/kamcore.lpr` — the engine as a shared library (`libkamcore.so`), `pascal/KM_AndroidExports.pas` — C API and touch gestures
- `pascal/shims/` — minimal replacements of the LCL units the engine uses (there is no LCL on Android)
- `../src/KM_MainAndroid.inc` — Android game loop (frames driven by `GLSurfaceView`)
- platform specific engine changes are under `{$IFDEF ANDROID}` / `{$IFDEF FPC}`
- rendering: the engine's desktop OpenGL (fixed function) runs on GLES2 through [gl4es](https://github.com/ptitSeb/gl4es)
  with two fixes (`toolchain/patches`)
- sound effects: OpenAL Soft; music: `native/bass_android.c` implements the BASS API subset the game uses
  (MP1/2/3 via minimp3, OGG via libvorbisfile)
- videos: libVLC for Android, as the Windows version uses VLC
- PascalScript gets aarch64 support for script event handlers (`toolchain/patches/pascalscript-aarch64.patch`)

## Known limitations

- Multiplayer is hidden (secure network auth unit is not part of the open source code).
- Saves/replays made by the Windows version may not load if scripts stored floating point
  values (80-bit `Extended` on Windows vs 64-bit on arm64).

## License

Same as KaM Remake: GNU AGPL v3 (see `LICENSE.txt` in the repository root).
Knights and Merchants is © its respective owners; its data is not included.

---

### По-русски

Нативный порт KaM Remake под Android (arm64), без эмуляции. Данных игры в репозитории нет: нужна своя копия
Knights and Merchants и установщик KaM Remake. Сборка: `android/toolchain/setup_toolchain.sh`, затем
`android/toolchain/extract_data.sh <установщик KaM Remake>`, затем `cd android && ./build_apk.sh`
(`KAM_BUNDLE_DATA=1` — APK со встроенными данными).

# KaM Remake for Android

Native Android (arm64) port of [KaM Remake](https://github.com/reyandme/kam_remake) — *Knights and Merchants*
on your phone, no emulator. Original graphics and interface; adapted for phones: screen rotation,
interface scale, touch controls.

**Game data is not included** — you need your own copy of *Knights and Merchants* and the
KaM Remake installer from [kamremake.com](https://www.kamremake.com/download/).

## Build (macOS)

Needs: `brew install fpc innoextract`, Android SDK with NDK 29.0.13599879 and CMake, JDK 17+.

```sh
git clone --recurse-submodules https://github.com/Vadim170/kam-remake-android.git && cd kam-remake-android
android/toolchain/setup_toolchain.sh                          # build tools, ~20 min, once
android/toolchain/extract_data.sh <KaM Remake installer>.exe  # game data from your installer
cd android && KAM_BUILD_TYPE=Release KAM_BUNDLE_DATA=1 ./build_apk.sh
```

## Install

Copy `android/app/build/outputs/apk/release/app-release.apk` to the phone and open it (or `adb install`).
On the first start the game unpacks its data (~1 min).

**Controls:** tap — click, long press — right click, pinch — zoom, drag — scroll, Back — Esc,
three-finger tap — interface size.

More: [android/README.md](android/README.md) · original readme: [README.KaM_Remake.md](README.KaM_Remake.md) · license: AGPL v3

---

**По-русски.** Нативный порт KaM Remake под Android (arm64), без эмулятора. Данных игры в репозитории нет —
нужна своя копия Knights and Merchants и установщик KaM Remake. Сборка — три команды выше, затем установить
APK на телефон; при первом запуске игра распакует данные. Управление: тап — клик, долгое нажатие — правый клик,
щипок — масштаб, «Назад» — Esc, тап тремя пальцами — размер интерфейса.

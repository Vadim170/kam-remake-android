#!/bin/bash
# Extracts the KaM Remake game data from the official Windows installer (kamremake.com)
# into $KAM_TOOLCHAIN/kamres/app. The data is not part of this repository.
# Usage: extract_data.sh path/to/kam_remake_installer.exe     (requires innoextract: brew install innoextract)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TC="${KAM_TOOLCHAIN:-$REPO/toolchain}"
INSTALLER="${1:?Usage: $0 kam_remake_installer.exe}"
command -v innoextract >/dev/null || { echo "innoextract is required: brew install innoextract"; exit 1; }
rm -rf "$TC/kamres"
mkdir -p "$TC/kamres"
innoextract -s -d "$TC/kamres" "$INSTALLER"
for d in data Campaigns Maps MapsMP Music Sounds Tutorials; do
  [ -d "$TC/kamres/app/$d" ] || { echo "Missing $d in the installer"; exit 1; }
done
echo "Game data extracted to $TC/kamres/app"

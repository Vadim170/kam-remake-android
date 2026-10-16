#!/bin/bash
# Build and show only the first errors
"$(dirname "$0")/build_native.sh" "$@" > "$(dirname "$0")/build/last.log" 2>&1; rc=$?
grep -E 'Error:|Fatal:' "$(dirname "$0")/build/last.log" | head -${N:-25}
echo "rc=$rc; compiled units: $(grep -c '^Compiling' "$(dirname "$0")/build/last.log")"

#!/bin/zsh
# Offline tests (no pedal needed): SysEx codec, packets, settings layout,
# and read/write logic against a fake pedal.
set -e
cd "$(dirname "$0")"
CACHE="${TMPDIR:-/tmp}/chocoedit-modcache"
mkdir -p "$CACHE"
[[ -f Sources/ChocoEdit/Version.swift ]] || ./build.sh >/dev/null
swiftc -module-cache-path "$CACHE" -suppress-warnings -o "$CACHE/chocoedit-tests" \
  Tests/main.swift Sources/ChocoEdit/{SysEx,MIDI,Pedal,Layout,Keys,Errors,Version}.swift
"$CACHE/chocoedit-tests"

#!/bin/sh
set -eu
ytmdir=$(mktemp -d "${TMPDIR:-/tmp}/ytm-global-test.XXXXXX")
xcrun clang -fobjc-arc -c src-tauri/native/touchbar/GlobalTouchBarBridge.m -o "$ytmdir/bridge.o"
swiftc -module-cache-path "$ytmdir/cache" tests/global-touchbar/main.swift "$ytmdir/bridge.o" -framework AppKit -o "$ytmdir/probe"
"$ytmdir/probe"

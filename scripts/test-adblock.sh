#!/bin/sh
set -eu
ytmdir=$(mktemp -d "${TMPDIR:-/tmp}/ytm-adblock-test.XXXXXX")
swiftc -module-cache-path "$ytmdir/cache" src-tauri/native/touchbar/AdBlocker.swift tests/adblock/main.swift -o "$ytmdir/test"
"$ytmdir/test"

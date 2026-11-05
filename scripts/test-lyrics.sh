#!/bin/sh
set -eu
ytmdir=$(mktemp -d "${TMPDIR:-/tmp}/ytm-lyrics-test.XXXXXX")
swiftc -module-cache-path "$ytmdir/cache" src-tauri/native/touchbar/NativeSafety.swift src-tauri/native/touchbar/Lyrics.swift src-tauri/native/touchbar/TTMLLyrics.swift tests/lyrics/main.swift -o "$ytmdir/test"
"$ytmdir/test"

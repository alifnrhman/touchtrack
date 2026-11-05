# Native Touch Bar lyrics

## Current behavior

Lyrics mode shows previous/play-pause/next, the current and next lyric lines, and a layout toggle. ⌘L performs the same toggle; the preference persists in UserDefaults. A red fill sweeps smoothly through the current text, using real segment start/end timestamps. Already-sung text stays filled; upcoming text remains dim. CoreText draws a fixed-weight glyph layout twice with a moving clip mask, so characters and font metrics do not jump per syllable. Long lines follow the moving fill edge continuously. Physical Touch Bar appearance has not been inspected by the agent.

The native service first calls Better Lyrics' documented public cached `/getLyrics` endpoint with song, artist, album and duration. Missing album skips that provider. A 401 cache miss, unavailable/malformed/low-confidence data or missing word timing falls back to LRCLIB's line-synced `/api/get`. No timing is fabricated for plain-only lyrics; an instrumental or unavailable result has an explicit status. Availability differs by song and provider cache.

Better Lyrics supplies word/syllable timestamps, not necessarily phoneme or character timings. Timing precision depends on the correct recording match, provider data, IPC/sample latency and a nominal 60 Hz render interval. Highlighting one syllable does not establish exact timing for each character in it.

## Data flow and performance

The adapter reads album links whether relative or absolute and emits album/playbackRate alongside player state. Rust bounds all metadata and normalizes invalid playback rates. Media play/pause/seek events update immediately; progress samples remain throttled. A native monotonic clock interpolates between samples at the player rate. The nominal 60 Hz local timer runs only during active rich-timed playback and stops when paused, disabled or the application is inactive. It does not poll WebKit or fetch lyrics repeatedly.

A 500 ms metadata debounce, generation checks, cancellation and a 40-entry memory cache prevent stale responses and redundant requests. All requests use fixed HTTPS endpoints, ephemeral cookie-free sessions, no redirects and 512 KiB response limits. Only song metadata goes to lyric providers; no Google credentials/cookies or browser tokens are sent. Disabling lyrics cancels pending work. Lyrics are not persisted to disk.

LRCLIB HTTP 503 receives at most two retries honoring Retry-After. HTTP 429 suppresses requests for at least Retry-After; delta-seconds and HTTP dates are supported. Better Lyrics 429/503 initiates a cooldown for that provider, with LRCLIB fallback. No authentication/rate-limit bypass is attempted. The development User-Agent identifies the application; add an actual project URL/contact before public release.

## Parser and rendering safety

LRC supports fractional timestamps, repeated timestamps per line, offsets and blank cues. TTML parsing preserves raw inter-span whitespace and UTF-16 text ranges, excludes background-vocal spans from the lead line, and avoids double-counting nested wrappers. Source size, depth, cue/segment counts and text lengths are bounded. DTD/entity declarations are rejected and external entity resolution is disabled. XML and lyric text are never executed as HTML or JavaScript.

Player Status reports provider, response status, album, cue count and active segment range. It does not dump lyrics or credentials. The app grants remote web content no new native capabilities.

## Verification

- Five adapter tests, three Rust tests and thirty Swift parser/timeline/decoding checks passed.
- Monokrom guest playback, native line metadata and progressing lyric cues were verified inside the application after restarting a stale build: HTTP 200, 31 LRCLIB cues, active cue 4 at 0:46.
- Better Lyrics' public request for Monokrom/Tulus/Monokrom/215 returned 34 TTML lines and 312 timed spans.
- The real native LyricsService subsequently returned `word-synced`, HTTP 200, 34 lines and an active UTF-16 segment range 5:3 at position 23 seconds. This verifies native provider parsing and highlight selection, not physical Touch Bar appearance or audible alignment.
- A live test on another song fell back to LRCLIB and encountered HTTP 503. Subsequent full-app verification on Monokrom showed word-synced, Better Lyrics HTTP 200, 34 cues and Album: Monokrom. Catalogue coverage remains unverified.
- Unit fixtures cover word boundaries, backward seeks, emoji ranges, nested spans, whitespace, malformed XML, entity rejection, and honest line-only fallback.

## Sources and attribution

The app uses the [Better Lyrics API](https://docs.betterlyrics.org/) and credits [Better Lyrics](https://betterlyrics.org/). No extension source code is bundled. See [response format](https://docs.betterlyrics.org/docs/response-format), [authentication](https://docs.betterlyrics.org/docs/authentication), and [LRCLIB API](https://lrclib.net/docs). Cached Better Lyrics data is publicly readable; fresh TTML fetches may require an API key, and new keys are currently not issued. The app does not require installing an extension or obtaining a key.

The final full-app Player Status confirmed the rich provider at song time 0:05 (before its first vocal cue). Active segment selection was separately verified by the native service test at 23 seconds. The final word-highlight DMG checksum passed hdiutil verification.

## Smooth karaoke rendering

The color boundary interpolates linearly across each timed segment, preserving completed fill through gaps. The provider timings still determine when each segment starts/ends; this visual interpolation does not claim per-character phonetic timestamps. Pause freezes the fill and backward seek rewinds it. Ten additional sweep checks passed for quarter/half/three-quarter progress, continuous segment boundaries, completed fill, pause, rewind, invalid time and no invented sweep on line-only lyrics. CoreText's glyph offsets are used for clipping and scrolling; the text is never reshaped by changing individual syllables to bold.

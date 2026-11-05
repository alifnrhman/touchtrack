# Architecture

Tauri v2 owns the window and WKWebView. TypeScript/Vite builds the injected adapter separately as `dist/player-adapter.js`. Cargo embeds that artifact, compiles the Swift source into a static library, and links AppKit, Foundation, WebKit and macOS system Swift runtimes. No Node or Rust runtime is shipped.

## State and commands

A main-frame-only WKUserScript runs in the named `YTMTouchBar` WKContentWorld. It reads the shared DOM and active video/audio element without relying on private YouTube JavaScript objects. Media events and a debounced MutationObserver discover track changes and replaced elements. Progress media events are throttled to one second. The adapter emits the PlayerState contract from `src/types/player.ts`.

Swift checks the frame's HTTPS origin before passing bounded JSON through the C ABI to Rust. Rust owns the latest typed state, rejects invalid numeric values and oversized text, normalizes seek bounds, and removes unapproved artwork URLs. Canonical state returns synchronously to Swift on the main thread to update existing native views.

Native Touch Bar and menu commands share the same Rust validation path. Only the six declared command kinds are accepted. A fixed JavaScript function receives structured arguments in the isolated content world. No script supplied by remote content is evaluated natively. Remote Tauri capabilities remain empty.

## Native interface

NSTouchBar uses NSCustomTouchBarItem, native buttons, two-line metadata, NSImageView and NSSlider. Essential playback controls have higher visibility priority than progress. Artwork requests use a cookie-free ephemeral session, HTTPS host allowlist, redirect checks, two-megabyte limits, cancellation and stale-result checks. Missing data produces disabled controls and a music-note placeholder.

AppKit updates execute on the main thread. A weak script handler avoids a WKWebView retain cycle. Window closure clears state, observations, artwork tasks and message handlers. Window geometry is persisted by AppKit; no credentials are stored by application code.

## Browser compatibility and authentication

The default WKWebView user agent received YouTube Music's deprecated-browser page on the test host. Appending `Safari/605.1.15 YTMTouchBar/0.1 WKWebView` allowed the public music interface to load and play. This is a compatibility adjustment, not an upgrade to WebKit or a claim that this is Safari. It is used only in the music window, whose top-level navigation is restricted to music.youtube.com.

Sign-in uses a separate standard WKWebView with its default user agent and no player scripts. No Safari compatibility token is applied to Google Accounts. Both views use default persistent WebKit storage. Authenticated playback and session persistence across an app restart were observed on the development host; broader compatibility remains unverified. No cookie copying or OAuth bypass exists. The music page's sign-in navigation is routed to the separate sign-in window. Returning to music closes that window; closing it reloads the main player.

## Limitations

DOM selectors may change. Ads can temporarily replace the media element or track timing. A forwarding navigation delegate preserves Tauri policy callbacks while presenting load failures and content-process termination with a native ⌘R retry message. These failure paths remain untested. The app must remain running for background playback; sleep and lock-screen behavior are not guaranteed. Normal Touch Bar controls belong to the active application; a separately authorized optional private-API global experiment is described in global-touchbar.md.

## Lyrics extension

The native controller now includes a native Better Lyrics TTML service with LRCLIB fallback, word/syllable highlighting and two-line lyric mode; see [lyrics.md](lyrics.md) for the provider boundary, timing logic, privacy, limits and actual verification. PlayerState adds a backward-compatible `isAd` field. No remote-content permissions were added.

## Native content blocking

A dedicated AdBlocker installs a compiled WebKit content rule list before the first music navigation. A checked native menu item toggles it and reloads the music page. The preference persists locally; sign-in and native lyric/artwork sessions are unaffected. Only bundled, music-scoped rules are used. No remote IPC permissions or system-wide network configuration are added. See adblock.md for filtering scope and coverage limits.

## Global presentation experiment

GlobalTouchBar manages runtime-checked system-modal presentation through an exception-guarded Objective-C bridge. It is opt-in, reasserts only on debounced focus/minimize events, suspends for inactive user sessions, and exposes disable controls in the bar and menu bar. The same validated playback and lyric pipelines remain in use. See global-touchbar.md for risks and evidence.

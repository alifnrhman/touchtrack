# Feasibility results — 2026-11-03

## Environment

macOS Sonoma 14.8.9; Apple M2 MacBook Pro; Swift 6.0.3; Node 24.22.1; Rust 1.99.1. Rust was installed during setup. The workspace initially contained no source files.

## Browser loading: resolved for guest playback

The first release app launched but received YouTube Music's “Your browser is deprecated” / “not optimised for your browser” page with the default WKWebView user agent. This initially blocked playback testing.

A subsequent controlled compatibility test appended `Safari/605.1.15 YTMTouchBar/0.1 WKWebView` to the default user agent. It did not change engines or impersonate Chrome. YouTube Music's original browsing interface then loaded in the actual app. A public-response comparison and the application's accessibility tree both confirmed the difference.

**The initial failure does not mean WKWebView cannot play YouTube Music.** Guest playback was observed passing ads and advancing through “Teh Hijau” to 2:22 / 3:33. Audio audibility was not independently recorded or measured; the player showed active playback and advancing media time.

## Player and native integration

The expanded app uses scoped WebKit scripts, validated Rust state, and a Swift/AppKit renderer. The native Player Status dialog displayed:

- Teh Hijau, Tulus (initial byline extraction also included album/year; subsequent selector narrowed artist to the first artist link)
- 0:06 / 3:33
- Paused
- Seek, Previous, Next supported

The native Play/Pause menu action (same Rust command route as the Touch Bar) changed the actual player to Play/paused. Native Next changed the URL and title to “Sesi Potret (feat. Ari Lesmana)” with a 4:03 duration. Previous reset that track's progress to zero; moving to an earlier track was not established by that single test. Physical Touch Bar rendering, touch interactions, artwork appearance and slider seeking have not been visually verified.

## Authentication: partial observation only

The music-window compatibility token is never used on Google Accounts. Top-level navigation of that window is restricted to music.youtube.com. A separate sign-in window uses default WKWebView identification with no injected player script and an explicit HTTPS navigation allowlist.

The standard sign-in window reached Google's own “Sign in to continue to YouTube” page and email/phone field. No `disallowed_useragent` rejection appeared at that initial step. No credentials were entered by the agent. The user elected to continue without signing in. Successful authentication, shared authenticated cookies, and restart persistence remain unverified.

Google's policy prohibits embedded user agents for OAuth: https://developers.google.com/identity/protocols/oauth2/policies . A displayed login form does not establish that the complete flow is supported. No user-agent rotation on authentication endpoints, cookie import, token extraction or credentials interception is implemented. If Google rejects the flow later, respect that restriction. A separately authorized browser-hosted design is a possible alternative; external-browser OAuth alone does not create a YouTube Music WebView session.

## Automated/build verification

- TypeScript checking and Vite production builds passed.
- Three adapter tests passed: typed state/playback/seeking, wrong-origin isolation, and missing media.
- Three Rust tests passed: invalid times, seek clamping/artwork restrictions, and unknown commands.
- Swift and Rust release compilation passed.
- `.app` and `.dmg` generated; the final DMG checksum verified with hdiutil.
- Release app launched on the build host without Node/Rust runtime processes.

## Outstanding hardware and lifecycle checks

Physical Touch Bar layout, all physical controls, native seek interaction, background/minimized playback, offline recovery, content-process recovery, authenticated persistence and clean-machine installation require further manual verification. Native loading/error/retry presentation exists but failure paths have not been exercised. No public signed/notarized release has been made.

# Build and release

Touchtrack is an experimental macOS portfolio project. Source publication and a signed public binary release are separate milestones. Current builds are unsigned and unnotarized.

## Build

Install Node.js/npm, stable Rust, and Apple Command Line Tools with Swift, then run:

```sh
npm ci
npm run app  # Touchtrack.app
npm run dmg  # app and DMG installer
```

Outputs are under `src-tauri/target/release/bundle/macos/` and `src-tauri/target/release/bundle/dmg/`. Mount the DMG and drag the app into Applications. Fully quit the previous app before launching a new build. End users do not need Node, Rust, Swift, extensions, or BetterTouchTool installed.

The development host builds Apple Silicon binaries. Intel builds require a separate target and remain unverified:

```sh
rustup target add x86_64-apple-darwin
npm run tauri build -- --target x86_64-apple-darwin --bundles app,dmg
```

Swift compilation follows the Rust target. Minimum supported macOS is 14.

## Verification status

| Area | Evidence and limits |
| --- | --- |
| Apple Silicon build | App packaging passed on the Sonoma development host |
| DMG packaging | Previously passed; regenerate from current source before distributing |
| Browsing and guest playback | Observed working |
| Signed-in playback | Observed working; existing session survived app restart |
| Player controls | Native play/pause and next exercised; comprehensive physical button tests remain open |
| Lyrics | Live Better Lyrics word timing and cue advancement observed; provider availability varies |
| Ad blocking | Enabled alongside authenticated playback; current coverage is image filtering plus video-ad skipping |
| Global Touch Bar | Visibility after switching apps/minimizing user-confirmed on the Sonoma test host |
| Intel, other macOS versions | Not verified |
| Clean-machine installation | Not verified |
| Signing and notarization | Not performed |
| Offline recovery, sleep/wake, lock/unlock | Broader testing remains open |

These observations apply to the development host. They do not guarantee compatibility with every Google account, ad format, Mac, or macOS release. Historical investigation is recorded in [feasibility.md](feasibility.md).

## Authenticated playback regression

Broad network rules previously stalled playback after login, leaving duration unavailable. Turning the blocker off and reloading restored playback. The current rules restrict blocking to image resources; scripts, raw/telemetry, media and documents remain allowed. The isolated video-ad skipping script stays active.

The revised app retained its signed-in session and played two tracks with `Ad blocker: On — ad images + player ad skipping`. Native Next changed tracks, and the next track advanced past 0:14 with word-synced lyrics. Eight JavaScript tests and seventeen native rule checks passed, including actual WebKit rule compilation. This establishes playback compatibility for the observed session, not complete live ad-removal coverage.

## Before distributing binaries

Run the checks in the README and verify the exact artifact you intend to upload. Test installation on a clean Mac, both target architectures you advertise, sign-in/session persistence, controls, and the experimental mode's disable/recovery behavior. Label unsigned artifacts as experimental.

For signed direct distribution, configure Developer ID Application signing, hardened runtime, and notarization following the [Tauri macOS signing guide](https://v2.tauri.app/distribute/sign/macos/). Keep signing credentials in the Keychain or CI secrets. Staple and verify the notarization ticket and Gatekeeper assessment before publishing. No signed/notarized artifact is currently supplied.

# Source hardening review

This review covers navigation, the player bridge, native HTTP clients, lyric parsing, artwork decoding and workflow dependencies. It is not a penetration test or a complete dependency vulnerability audit.

## Changes

| Boundary | Finding | Hardening |
| --- | --- | --- |
| Music WebView navigation | Music host checks did not consistently reject nonstandard ports or URL credentials; local custom-scheme hosts were unrestricted | Exact HTTPS origin checks, restricted bootstrap hosts, development server limited to debug mode, explicit denial of sign-in popups |
| Lyrics retry scheduling | Server-controlled Retry-After could schedule an excessive delay | Numeric and HTTP-date delays bounded to 1–300 seconds; nonfinite values rejected |
| Artwork decoding | Compressed-byte limit did not bound decoded image dimensions | Reject edges above 8192 px or more than 16 million pixels, then decode one thumbnail no larger than 128 px |
| Player bridge | Artwork URLs were not truncated before native serialization | Drop URLs longer than 4096 characters before posting state |
| CI/release actions | Mutable major-version action tags | Pin checkout/setup-node to the resolved full commit SHAs |

Tests cover origin confusion, credential-bearing and nonstandard-port URLs, production/development bootstrap separation, malicious retry values, invalid/oversized artwork and real PNG thumbnail decoding.

## Existing protections retained

- Remote Tauri capabilities are empty. The player bridge runs in an isolated content world, accepts main-frame messages only, and validates the music HTTPS origin.
- Rust rejects unknown command fields, invalid numeric state and oversized metadata; seek commands are bounded.
- Artwork hosts and redirects are allowlisted. Native requests use ephemeral sessions without Google cookies and have byte/time limits.
- Lyrics endpoints are fixed, redirects are denied, responses are bounded, and TTML rejects document types/entities with depth, text, segment and line limits.
- Global Touch Bar behavior is opt-in, runtime-checked and isolated behind an Objective-C exception boundary.

## Remaining limits

Remote sites, providers and WebKit remain dependencies. Keep macOS and dependencies updated. Private Touch Bar APIs are inherently unsupported. Signing/notarization, broader login/hardware testing, dependency advisories and clean-machine installation still require separate work.

The v0.1.0-beta.1 binary predates these hardening changes. Source changes require a fresh build and a new release; do not replace an existing release artifact silently.

References: [Apple ImageIO thumbnail limits](https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize), [Tauri popup policy](https://docs.rs/tauri/latest/tauri/webview/enum.NewWindowResponse.html), [GitHub Actions security guidance](https://docs.github.com/en/actions/reference/security/secure-use).

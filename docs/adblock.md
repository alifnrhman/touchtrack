# Native ad blocking

The application includes an optional WKContentRuleList-based blocker. **Block Ads (reloads music)** in the native application menu toggles it, and the preference persists in UserDefaults. It defaults to enabled. Toggling reloads the music page and may interrupt the current track.

Six bundled image-only network rules target advertising domains (DoubleClick, Google Syndication, Google Ad Services) and specific YouTube ad/telemetry paths. Rules are scoped to music.youtube.com and installed only in the music WKWebView. The separate standard sign-in window has no blocker. Scripts, raw requests (including ad telemetry), documents and media remain allowed even on advertising endpoints. Blocking those requests stalled authenticated playback on the test host; video ads are handled by the isolated player script instead. Music-stream hosts, YouTube player API endpoints and lyric providers are not blocked.

Compilation completes before the first remote music navigation. If compilation fails, the app continues without blocking and Player Status explicitly reports that the rules failed. Disabling removes only this application's rule list; it does not clear unrelated WebKit settings or website storage. Generation checks prevent an old compilation callback from installing rules after a newer toggle.

No extension, proxy, DNS configuration, downloaded filter feed, certificate installation, additional runtime or privileged background process is used. Network rules are deliberately conservative. A separate script in an isolated WebKit world checks the music player every 500 ms and on media events. While the player explicitly reports `ad-showing`, it clicks a skip button when available, or seeks finite, playing ad media to its end. It leaves normal songs, paused media, live streams and unknown durations alone. Disabling the blocker removes this script for the reloaded page and preserves other user scripts. Authentication behavior is unchanged. They do not provide a guarantee of ad-free YouTube playback: ads delivered through shared player/media paths may still appear, and YouTube can change its implementation or show ad-blocker notices. Disable the blocker and reload if playback breaks.

## Verification

`npm run test:adblock` checks seventeen positive/negative URL, resource-type and document-scope cases, including nested ad domains, domain-boundary confusion, Google Video streams, player API and auth exclusions. The test also invokes the actual WKContentRuleListStore compiler; WebKit accepted the final rules. An earlier draft used regex alternation unsupported by WebKit; it was replaced with separate rules before packaging.

`npm test` also checks player ad skipping, ordinary-song preservation, skip transitions, paused/live media and origin restrictions. These tests establish fixture behavior, rule matching and compilation. They do not measure live ad-removal coverage or guarantee that every ad request is prevented. See release.md for live application checks.

Public APIs: [WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore), [WebKit content blockers](https://webkit.org/blog/3476/content-blockers-first-look/).

The packaged app was subsequently launched with rules enabled. Native Player Status confirmed successful installation, and Monokrom advanced to 0:09 / 3:35. Live filtering coverage, every ad format, and toggle/restart persistence have not been separately measured; preference persistence and toggling are implemented.

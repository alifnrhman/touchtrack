# Experimental global Touch Bar

The user explicitly authorized a private-API experiment after the public NSTouchBar limitation was explained. Normal mode remains the default. Enable **Keep Touch Bar Visible (Experimental)** from the application menu or the **♫** menu-bar item. This preference persists on this Mac.

## Implementation

A small Objective-C bridge dynamically checks modern and legacy system-modal NSTouchBar selectors, validates argument counts and the placement/return encodings, and catches Objective-C exceptions. It requests placement 0 with no tray identifier. Unsupported or failed presentation returns to normal mode. No private framework is linked, no system binaries/settings are modified, and no additional application or daemon is installed.

The driver transfers ownership of the bar from the app window to a system-modal presentation. It keeps the normal responder provider from creating another bar while global mode owns the views. Layout changes dismiss the old bar before creating the replacement; disabling dismisses before restoring the ordinary app bar.

App activation and window-minimize notifications trigger one debounced re-presentation, not a keep-alive polling loop. User-session deactivation dismisses and suspends it. Only a session-activation notification lifts that suspension; other-app activation or wake does not lift it while the session is suspended. The experiment does not intentionally activate the music app or bring its window forward. The lyrics render clock remains active in the background only while a global presentation is requested and the user session is active.

## Exit and recovery

- Choose **♫ → Restore Normal Touch Bar** from any app.
- Uncheck **Keep Touch Bar Visible (Experimental)** in either menu.
- Quit YouTube Music to dismiss and release the modal bar.

Only the native system close button is shown; the redundant custom × beside the lyrics toggle has been removed. The system close button remains available; no DFR function hides it. Re-presentation is event-driven and may restore the bar after a later focus switch, so use one of the explicit off controls to keep it disabled. Closing the music window tears down the driver. Quitting does not erase the user's saved enabled preference; a subsequent launch tries to restore it if the selectors still exist.

## Limits

This is not supported by Apple's public AppKit contract. Private API availability and visual behavior can change with macOS updates, and selectors returning successfully do not prove that the physical Touch Bar is showing our bar. Other global Touch Bar tools, Fn/system controls and system-modal UI can take precedence. No claim is made for lock-screen rendering or exclusive/global visibility in every situation. Controls remain local to this app's player; it does not intercept other apps' controls or credentials.

Private-API builds are not suitable for claiming Mac App Store compliance. Signing/notarization status is unchanged: current builds are unsigned and unnotarized. Physical visibility was subsequently confirmed by the user in the live test below; broader OS/session behavior remains unverified.

## Tests

`npm run test:global` performs a capability-only probe and never presents a bar or changes preferences. On the Sonoma 14.8.9 host, modern/legacy presentation and dismissal selectors were present and the validated bridge reported supported. App/DMG build and live UI checks are recorded in release.md.

API-signature research used public source in [PersistentTouchBarDriver](https://github.com/benjaminbelaga/comux/blob/main/Sources/App/Views/TouchBar/PersistentTouchBarDriver.swift). No source from that implementation was bundled. Public behavior is described in Apple's [NSTouchBar documentation](https://developer.apple.com/documentation/appkit/nstouchbar).

## Live test — Sonoma 14.8.9

The experimental menu option was enabled through the actual app UI. Player Status reported `Global requested — experimental · Supported: true`. The music window was minimized and Finder was selected as the other application. The user was asked to switch to Chrome/another app and check the physical Touch Bar, and answered **“Masih terlihat”** (“still visible”). This is user-reported confirmation of physical global visibility, not an image captured by the agent.

The option remains enabled on this Mac. Normal-mode restoration, sleep/wake, locking/unlocking, full-screen spaces, competing Touch Bar tools and background button interactions have not been separately exercised. The probe only verifies API availability/signature checks; it does not substitute for that physical test.

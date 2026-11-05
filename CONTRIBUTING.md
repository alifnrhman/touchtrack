# Contributing to Touchtrack

Start with the setup and checks in [README.md](README.md). Development and native tests require macOS; physical Touch Bar behavior requires compatible hardware.

For bug reports, include your macOS version, Mac architecture, app version, whether you are signed in, whether ad blocking/global Touch Bar is enabled, and steps to reproduce. Remove account names, email addresses, private playlists, cookies and credentials from screenshots or logs before sharing them.

For code changes, describe the problem, resulting behavior, and checks you ran. Distinguish fixture tests from live playback and physical hardware verification. Keep credentials, build products, website storage and local diagnostics out of the repository.

Do not add cookie imports, credential collection, or authentication-policy bypasses. Changes to network filtering should preserve authenticated playback and include resource-type regression checks.

Contributions are provided under the project's [MIT License](LICENSE).

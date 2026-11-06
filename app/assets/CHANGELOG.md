# Changelog

## 1.0.0

- Initial release of LocalSend X, an independent fork of LocalSend.
- Lowers the minimum supported Android version to 5.0 (API 21); ships 32-bit, 64-bit and x86_64 APKs.
- Renamed the app to LocalSend X with a new package id (`io.github.jingrongx.localsend`), so it can be installed alongside the official LocalSend app.
- Added an in-app updater: automatic check on startup (optional), manual check in the settings tab, automatic download and install prompt.
- Releases are built and published automatically by GitHub Actions for every `v*` tag.
- Removed upstream donation, in-app purchase, and What's New features.
- Based on LocalSend 1.18.x (protocol v2, still compatible with the official app).

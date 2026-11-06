# Changelog

## 1.0.1

- Fixed the startup crash on Android 5.x/6.x (`cannot locate symbol "getifaddrs"`): network interfaces are now enumerated via netlink on Android instead of `getifaddrs(3)`, which only exists since Android 7.0 (API 24).
- The `if-addrs` and `webrtc-util` Rust dependencies are patched locally under `support/patches/` to provide this.

## 1.0.0

- Initial release of LocalSend X, an independent fork of LocalSend.
- Lowers the minimum supported Android version to 5.0 (API 21); ships 32-bit, 64-bit and x86_64 APKs.
- Renamed the app to LocalSend X with a new package id (`io.github.jingrongx.localsend`), so it can be installed alongside the official LocalSend app.
- Added an in-app updater: automatic check on startup (optional), manual check in the settings tab, automatic download and install prompt.
- Releases are built and published automatically by GitHub Actions for every `v*` tag.
- Removed upstream donation, in-app purchase, and What's New features.
- Based on LocalSend 1.18.x (protocol v2, still compatible with the official app).

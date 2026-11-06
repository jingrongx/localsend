# Local patch of `webrtc-util` 0.12.0

Copied from the published crate of the same version, with one divergence:

**On Android, `ifaces::ifaces()` enumerates via the (patched) `if-addrs`
crate instead of `nix::ifaddrs`.**

`nix::ifaddrs` calls `getifaddrs(3)`, which only exists in bionic (Android's
libc) since API 24 (Android 7.0). Any dynamic library that references it
fails to load on older devices with `dlopen failed: cannot locate symbol
"getifaddrs"`, regardless of whether the code path is ever executed — rustc
keeps dependency code in the cdylib even when unreferenced. LocalSend X
still supports Android 5.0+ (API 21), so the reference must not exist.

The Android implementation maps the `if-addrs` results (netlink-based on
Android — see `../if-addrs/README-PATCH.md`) onto the crate's `Interface`
type. The runtime consumer, `webrtc-mdns`, only reads `addr` to join the
mDNS multicast group per IPv4 interface, which this mapping provides.

Changes:

- `src/ifaces/ffi/unix/mod.rs`: original nix implementation kept for
  non-Android unix; Android implementation added. Everything else is
  upstream code, untouched.
- `Cargo.toml`: android-scoped `if-addrs` dependency added, and the `nix`
  dependency is excluded on Android. `webrtc-util` is nix 0.26.4's only
  dependent in this workspace, so nix drops out of the Android build
  entirely — necessary because rustc links dependency rlibs whole-archive,
  which would keep nix's `getifaddrs` import alive even with the module
  unused.

Activated via `[patch.crates-io]` in the workspace root `Cargo.toml`.
If the crate is ever updated, check whether upstream moved off
`nix::ifaddrs` on Android before dropping this patch.

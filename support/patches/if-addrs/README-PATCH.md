# Local patch of `if-addrs` 0.15.0

Copied from the published crate of the same version, with one divergence:

**Android interface enumeration uses netlink (RTM_GETLINK / RTM_GETADDR)
instead of `getifaddrs(3)`.**

`getifaddrs(3)` only exists in bionic (Android's libc) since API 24
(Android 7.0). Any dynamic library that references it fails to load on older
devices with `dlopen failed: cannot locate symbol "getifaddrs"`. LocalSend X
still supports Android 5.0+ (API 21), so referencing that symbol is not an
option: rustc links rlibs into the cdylib whole-archive, which keeps the
crate's `get_if_addrs` (and its `getifaddrs` import) alive in the final
library even when no code calls it.

Changes:

- `src/netlink.rs` (added): netlink-based enumeration of links and addresses,
  producing the same `Vec<Interface>` as the upstream implementation.
- `src/lib.rs`: `posix` and `getifaddrs_posix` are excluded on Android;
  `get_if_addrs()` dispatches to `netlink` there. Everything else is
  upstream code, untouched.

Activated via `[patch.crates-io]` in the workspace root `Cargo.toml`.
If the crate is ever updated, re-check that the upstream version did not
gain a fallback for old Android before dropping this patch.

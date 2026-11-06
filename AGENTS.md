# AGENTS.md

This file provides guidance to LLMs when working with code in this repository.

LocalSend X is an independent fork of [LocalSend](https://github.com/localsend/localsend) (Apache-2.0). It targets **Android only** for releases and pins the toolchain to **Flutter 3.32.8** so that `minSdk 21` (Android 5.0) stays supported — newer Flutter versions require API 24+, so do not bump Flutter without re-verifying the Android floor. The protocol layer stays compatible with upstream LocalSend.

## Repository layout

This is a multi-language monorepo: a Flutter app on top of a Rust protocol implementation.

| Path                           | What it is                                                                                                                                                  |
|--------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `app/`                         | The Flutter app (`localsend_app`, package id `io.github.jingrongx.localsend`). UI, providers, persistence, platform channels.                                |
| `packages/localsend_isolates/` | Dart isolate layer + `flutter_rust_bridge` (FRB) bindings. Owns `rust/` (the Flutter plugin crate `rust_lib_localsend_app`) and `rust_builder/` (cargokit). |
| `packages/core/`               | Rust crate `localsend`: protocol, HTTP server/client, crypto, WebRTC. No Flutter dependency.                                                                |
| `packages/typed_isolates/`     | Small standalone package wrapping Dart `Isolate` with typed send/receive channels.                                                                          |
| `server/`                      | Axum WebSocket signaling server for WebRTC (`/v1/ws`). Deployed separately, see `server/Dockerfile`.                                                        |
| `cli/`                         | Rust CLI crate (`localsend-cli`). Kept from upstream; not part of the fork's release pipeline.                                                              |
| `support/scripts/`             | Packaging scripts (upstream leftovers; not used by the fork's CI).                                                                                          |

The four Rust crates (`packages/core`, `packages/localsend_isolates/rust`, `server`, `cli`) form a single Cargo workspace rooted at the repository root: one shared `Cargo.lock` and `target/`, and `[profile.*]` settings live only in the root `Cargo.toml` (member profiles would be ignored). Cargokit still builds the plugin crate into its own target dir during Flutter builds.

The three Dart packages (`app`, `packages/localsend_isolates`, `packages/typed_isolates`) form a pub workspace rooted at the repository root: one shared `pubspec.lock` and `.dart_tool/`, resolved by running `pub get` from any member. `rust_builder` and the vendored `cargokit/build_tool` are deliberately not members and still resolve standalone.

Dependency direction: `app` → `localsend_isolates` → (`typed_isolates`, `rust_lib_localsend_app` → `localsend` core).
The app depends on **only** `localsend_isolates` — not on `flutter_rust_bridge`, `typed_isolates`, or the plugin crate directly.

## Flutter version

Pinned to **3.32.8** in `.fvmrc` (mirrored in `.github/workflows/ci.yml`, `app/pubspec.yaml`, plus the `support/submodules/flutter` git submodule). Use **`fvm flutter` / `fvm dart`**. Bumping means updating all four places — but remember Flutter ≥ 3.35 raises the Android min API to 24.

## Platform detection

Use `Theme.of(context).platform` for platform-specific styling in Material widgets, and `defaultTargetPlatform` for platform behavior in lower layers. Use `dart:io.Platform` for OS-specific native APIs: with the `FLUTTER_TEST` environment variable and assertions enabled, `defaultTargetPlatform` is set to Android regardless of the actual OS (unless `debugDefaultTargetPlatformOverride` is set).

## Commands

Run from `app/` unless stated otherwise.

```bash
fvm flutter pub get
fvm dart run build_runner build  # dart_mappable, freezed (flutter_gen was removed from the build chain)
fvm dart run slang               # i18n codegen (slang_build_runner is not a dependency anymore)
fvm flutter run
```

Checks (what CI runs):

```bash
rm -rf lib/gen && fvm dart format --set-exit-if-changed lib test   # generated code is not format-checked
fvm flutter analyze
fvm flutter test
fvm flutter test test/unit/util/security_helper_test.dart          # single file
fvm flutter test --plain-name 'some test name'                     # single test
```

Formatting is **150 columns** (`page_width: 150` in `analysis_options.yaml`, `trailing_commas: preserve`).

Rust:

```bash
cargo test --features full       # in packages/core — see "Core crate features" below
cargo clippy --features full
cargo check                      # in packages/localsend_isolates/rust, server, cli
```

FRB codegen — run from `packages/localsend_isolates/`:

```bash
flutter_rust_bridge_codegen generate    # config in flutter_rust_bridge.yaml (dart_format_line_length: 150)
```

`packages/localsend_isolates` has its own `build.yaml` and needs its own `build_runner` run when its models change (`pub get` is shared via the pub workspace).

## Codegen notes (fork-specific)

- `flutter_gen_runner` and `slang_build_runner` are **not** dev dependencies anymore: recent versions of both use a `build.yaml` schema that the current `build_runner` rejects, and their dependency chains cannot be resolved on Dart 3.8. `app/lib/gen/assets.gen.dart` is committed; regenerate it with the standalone `fluttergen` CLI (`dart pub global activate flutter_gen`) when assets change. Slang is always run via `dart run slang`.
- `app/lib/util/navigation_compat.dart` backports `NavigateAction.popUntil`/`popUntilRoot` from refena_flutter 3.4 (which requires Dart 3.11). Use `NavigateActionCompat` instead of `NavigateAction` for those two actions.

## Core crate features

`packages/core` gates almost everything behind Cargo features (`crypto`, `http`, `multicast`, `webrtc`, `webrtc-signaling`, `full`), and `default = []`. **Always build and test it with `--features full`.** A bare `cargo check`/`cargo build` fails because modules are declared unconditionally while their dependencies are optional — that is pre-existing and expected, not a regression.

## Architecture

### State management

Refena (`refena_flutter`), not Riverpod. Providers live in `app/lib/provider/`; `NotifierProvider` for plain state, `ReduxProvider` + dispatched action classes for anything the isolate layer touches. `app/lib/config/init.dart` (`preInit`) is the bootstrap: it initialises logging, `RustLib.init()`, persistence, the isolate container, tray/window, and returns the `RefenaContainer` that `main.dart` mounts. `postInit` (called from `HomePage.initState`) runs one-shot startup tasks — the in-app update check is dispatched there.

Models are `dart_mappable` (`@MappableClass`, `.mapper.dart` parts) with renamed methods — `fromJson`/`toJson` are the **Map** converters and `deserialize`/`serialize` are the string ones (configured in both `build.yaml` files). Freezed is used for FRB-adjacent unions.

### Isolates

The heavy networking never runs on the main isolate. `packages/localsend_isolates/lib/src/isolate/`:

- `parent/parent_isolate_provider.dart` — `ParentIsolateState` holds one `IsolateConnector` per child (http scan discovery, multicast discovery, http upload, http server) plus a `SyncState` mirrored into every child. `IsolateSetupAction` spawns them.
- `parent/actions.dart`, `parent/actions_sync.dart` — the only supported way for the app to talk to the children.
- `child/*_isolate.dart` — child entry points; they translate typed task messages into calls on `lib/src/task/`.
- `lib/src/task/` — pure helpers only; **isolate logic is prohibited there** (see its `README.md`).

State that children need (alias, port, protocol, whether the server runs, whether web send is on) is pushed via `IsolateSyncServerStateAction`. Children read `syncState` at start, so sync **before** starting the server.

### Networking (Rust)

The HTTP server and client are Rust, not Dart. `packages/core/src/http/server/` implements protocol v2 (v1 endpoints are not served) plus the "web send" download flow (`server/web.rs`) and an internal `show` endpoint used to foreground an already-running instance.

Integration is channel-based: `start_with_port` takes a `ServerConfigV2 { pin, event_tx, web_send }` and emits `ServerEventV2` events (`Register`, `PrepareUpload` with a `decision_tx` oneshot, `FileUpload` with a byte stream + `result_tx`, `PrepareDownload`, `SessionEnd`, `PrepareUploadAborted`, `CancelReceived`). Only **one upload session is active at a time**; cancellation safety comes from drop guards (`PendingSessionGuard`, `UploadGuard`, `PendingWebSessionGuard`). There is deliberately no `auto_accept` in core — the app auto-accepts by answering `decision_tx` immediately. New server→app interactions should extend `ServerEventV2` rather than adding side channels.

The FRB layer (`packages/localsend_isolates/rust/src/api/server.rs`) exposes `start_server` + an opaque `RsHttpServer` whose `listen` merges the v2, web-send and internal channels into one `RsServerEvent` stream; responder oneshots stay on the Rust side. On the Dart side `child/server_isolate.dart` turns those into `HttpServerEvent`s, which `app/lib/provider/network/server/server_provider.dart` routes to `ReceiveController` / `SendController` — these are **event handlers, not route handlers**.

Save targets are decided in Dart (`prepareFileSaveTarget`) and written by Rust: a path, or an Android SAF file descriptor obtained through the `io.github.jingrongx.localsend/localsend` method channel. Gallery saves go through a cache file first.

Server event `ip`s are `PeerIp` (IP + IPv6 scope): a link-local peer renders as `fe80::1%3`, which the HTTP client accepts back as a host, so event ips stay dialable.

TLS uses per-device on-the-fly certificates with **mandatory client certificates** (optional while the web pages are served, so browsers can connect); the peer identity is the uppercase-hex SHA-256 of the client cert DER, and `Register` is simply not emitted when a payload's claimed fingerprint disagrees with the cert. Prefer `event.certFingerprint ?? event.info.fingerprint` — the payload fallback only exists for encryption-off mode.

Both the receive pin and the web-send pin are fixed at server start, so changing either restarts the server.

Web assets for the browser download page are embedded from `packages/core/assets/web/`.

### Multicast discovery (Rust)

`packages/core/src/multicast/` (feature `multicast`, independent of `http`) implements UDP multicast discovery for protocol v2.2 — v1 messages are not parsed.
Integration mirrors the HTTP server: `multicast::start` takes a `MulticastConfig { group, group_v6, port, interface_filter, device, event_tx }` and emits `MulticastEvent::Discovered { ip, message }`; the returned `MulticastHandle` offers `announce` (the announcement burst) and `wait_stopped`.

UDP is **announce-only**: responses go back over HTTP as a unicast register request to the announcing device.

One socket is bound per interface IPv4 address (`SO_REUSEPORT`/`SO_REUSEADDR` + `IP_MULTICAST_IF`), because a single socket only sends on one interface. Multicast loopback stays on so that instances on one host see each other; own messages are dropped by fingerprint. IPv6 is a LocalSend extension (group `ff12::fd3a:e420`, `DEFAULT_MULTICAST_GROUP_V6`), enabled by setting `group_v6`: one `IPV6_V6ONLY` socket per interface, joined by interface index. `Discovered` carries the source's scope ID (interface index), which link-local IPv6 sources need for the HTTP answer.

### Signing & release

- Release signing reads `app/android/key.properties` (gitignored; template: `app/android/key.properties.template`). `storeFile` is resolved relative to `app/android/` (the Gradle root project). CI decodes it from the `ANDROID_KEY_PROPERTIES` + `ANDROID_KEY_STORE` GitHub secrets.
- `v1SigningEnabled` + `v2SigningEnabled` are both forced on: Android < 7.0 only verifies v1 signatures.
- Release flow: push a `v*` tag matching `app/pubspec.yaml`'s version → `.github/workflows/release.yml` builds three signed APKs and publishes a GitHub Release named `LocalSendX-<version>-android-<abi>.apk`. The in-app updater (see below) matches those asset names.

### In-app updates

`app/lib/provider/update/` checks `https://api.github.com/repos/jingrongx/localsend/releases/latest`. Auto-check on startup is a settings toggle (`autoCheckUpdates`); a manual check lives in the settings tab. New versions are downloaded automatically and installed via `app/lib/util/native/open_file.dart` (which requests `REQUEST_INSTALL_PACKAGES`). Update UI strings live under the `update` i18n key.

### i18n

Slang, source files in `app/assets/i18n/` (`<locale>.json` plus `_missing_translations_<locale>.json`), generated output in `app/lib/gen/`. `ga` (Irish) was removed because Flutter 3.32 does not support it. `app/test/unit/i18n_test.dart` guards the locale set.

## Release notes

`app/pubspec.yaml`'s version must match the pushed `v*` tag (CI fails otherwise) and is the source for the GitHub Release title and the in-app update comparison. The upstream version-consistency checks (Inno Setup, CLI Cargo.toml, MSIX) were removed together with those build pipelines; their files remain but are not shipped by this fork.

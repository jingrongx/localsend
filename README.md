# LocalSend X

<p align="center">
  <img src="app/assets/img/logo-512.png" alt="LocalSend X logo" width="160"/>
</p>

[![CI](https://github.com/jingrongx/localsend/actions/workflows/ci.yml/badge.svg)](https://github.com/jingrongx/localsend/actions/workflows/ci.yml)
[![Release](https://github.com/jingrongx/localsend/actions/workflows/release.yml/badge.svg)](https://github.com/jingrongx/localsend/actions/workflows/release.yml)

**LocalSend X** 是 [LocalSend](https://github.com/localsend/localsend)（Apache-2.0）的独立分支，聚焦 Android 平台，专为老旧设备与电视盒子优化。

- 📱 **最低支持 Android 5.0（API 21）**——上游 LocalSend 从 3.35 版 Flutter 起已放弃 Android 5.x/6.x 设备，本分支继续支持
- 📺 **兼容电视盒子**：同时提供 32 位（armeabi-v7a）、64 位（arm64-v8a）与 x86_64 APK，启用 v1+v2 双签名（Android 6 及以下只认 v1）
- 🔄 **与官方 LocalSend 互通**：协议层保持 v2 兼容（HTTPS + 证书指纹校验），可与官方版互传文件
- ⬆️ **应用内更新**：启动时自动检查（可关闭）+ 设置页手动检查，发现新版本自动下载后一键安装
- 🚀 **自动发版**：推送 `v*` 标签即自动构建签名 APK 并发布 GitHub Release

## 下载

前往 [**Releases**](https://github.com/jingrongx/localsend/releases) 下载最新 APK：

| 文件名后缀 | 适用设备 |
|-----------|---------|
| `android-arm32v7.apk` | 32 位手机、老旧电视盒子 |
| `android-arm64v8.apk` | 64 位手机、新款电视 |
| `android-x64.apk` | x86_64 模拟器、Intel 平板 |

也可以在应用内「设置 → 检查更新」直接升级。

> 包名为 `io.github.jingrongx.localsend`，与官方 LocalSend（`org.localsend.localsend_app`）**可以同机共存**。

## 从源码构建

工具链：Flutter **3.32.8**（见 `.fvmrc`）、JDK 17、Rust stable（版本由 `rust-toolchain.toml` 钉住）、Android SDK（NDK 随构建自动选择）。

```bash
git clone --recurse-submodules https://github.com/jingrongx/localsend.git
cd localsend
fvm install                 # 按 .fvmrc 安装 Flutter 3.32.8
fvm flutter pub get         # 在仓库根目录执行（pub workspace）
```

日常开发（在 `app/` 下执行，详见 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [AGENTS.md](AGENTS.md)）：

```bash
fvm dart run build_runner build   # dart_mappable / freezed 代码生成
fvm dart run slang                # i18n 代码生成
fvm flutter analyze
fvm flutter test
fvm flutter run                   # 真机/模拟器运行
```

构建 APK：

```bash
cd app
fvm flutter build apk --split-per-abi --release
```

## 发版与签名

发版签名密钥通过仓库 Secrets（`ANDROID_KEY_STORE`、`ANDROID_KEY_PROPERTIES`）注入，CI 自动解码并签名。

发布新版本：

1. 更新 `app/pubspec.yaml` 的 `version`（如 `1.0.1+2`）和在 `app/assets/CHANGELOG.md` 中添加更新说明（应用内更新页会展示）；
2. 提交并推送标签：`git tag v1.0.1 && git push origin main v1.0.1`（标签必须与 pubspec 版本一致，否则构建失败）；
3. GitHub Actions 自动构建三个 ABI 的签名 APK 并创建 Release。

本地构建签名 APK 时，复制 `app/android/key.properties.template` 为 `app/android/key.properties` 并填入自己的密钥（该文件已被 gitignore）。

## 项目结构

| 路径 | 说明 |
|------|------|
| `app/` | Flutter 应用（Android 为主，其余平台源码保留但不随本分支发版） |
| `packages/localsend_isolates/` | Dart isolate 层 + flutter_rust_bridge 绑定（Rust HTTP/组播） |
| `packages/core/` | Rust 协议核心（协议 v2、WebRTC、多播发现） |
| `packages/typed_isolates/` | 类型化 Dart Isolate 封装 |
| `server/` | WebRTC 信令服务器（自部署用，见 `server/Dockerfile`） |
| `cli/` | Rust 命令行客户端（沿用上游，不在发版流水线内） |

## 与上游的差异

- Flutter 3.41 → 3.32.8（最后一个支持 minSdk 21 的稳定版），配套依赖降级
- 移除捐赠/内购、What's New、F-Droid/winget/桌面平台发版流水线
- 应用内新增基于 GitHub Releases 的自动更新
- 品牌与包名更换，避免与官方版冲突

## 许可证

本项目沿用 [Apache-2.0](LICENSE) 许可证。基于 [LocalSend](https://github.com/localsend/localsend) 修改，原作者 Tien Do Nam 及上游贡献者的版权声明保留于 [LICENSE](LICENSE)。

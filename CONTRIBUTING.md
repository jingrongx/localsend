# Contributing to LocalSend X

这是 LocalSend 的独立 fork（LocalSend X），欢迎 Issue 与 PR。

## 运行

工具链要求见 [README](README.md)：Flutter 3.32.8（用 `fvm` 管理）、JDK 17。

```shell
cd app
fvm flutter pub get
fvm dart run build_runner build -d
fvm dart run slang   # 修改 assets/i18n 后执行
fvm flutter run
```

## 提交前检查

```shell
cd app
fvm dart format --set-exit-if-changed lib test   # 先 rm -rf lib/gen
fvm flutter analyze
fvm flutter test
```

格式化宽度为 150 列（见 `analysis_options.yaml`）。

## 版本发布

1. 更新 `app/pubspec.yaml` 的 `version`（格式 `x.y.z+build`）。
2. 提交后打标签并推送：`git tag v1.2.3 && git push origin v1.2.3`（标签必须与 pubspec 版本一致）。
3. GitHub Actions 自动构建三个 ABI 的签名 APK 并创建 Release。

## 签名密钥

本地构建签名 APK 需要 `app/android/key.properties`（模板见 `app/android/key.properties.template`），该文件与密钥库均已 gitignore，切勿提交。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:localsend_app/pages/update/update_page.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/update/update_utils.dart';
import 'package:localsend_app/provider/version_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The GitHub repository that publishes releases for this fork.
const kUpdateRepo = 'jingrongx/localsendx';

/// The file name prefix of the release APKs, e.g. "LocalSendX-1.2.3-android-arm64v8.apk".
const kReleaseAssetPrefix = 'LocalSendX-';

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  downloaded,
  error,
}

class ReleaseInfo {
  final String tagName;
  final String version;
  final String? changelog;

  /// Download URL of the APK matching the current device ABI.
  final String apkUrl;
  final int apkSize;

  ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.changelog,
    required this.apkUrl,
    required this.apkSize,
  });
}

class UpdateState {
  final UpdateStatus status;
  final ReleaseInfo? release;

  /// 0..1 while [UpdateStatus.downloading].
  final double downloadProgress;

  /// Path of the downloaded APK while [UpdateStatus.downloaded].
  final String? downloadedApkPath;
  final Object? error;

  const UpdateState({
    required this.status,
    this.release,
    this.downloadProgress = 0,
    this.downloadedApkPath,
    this.error,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    ReleaseInfo? release,
    double? downloadProgress,
    String? downloadedApkPath,
    Object? error,
  }) {
    return UpdateState(
      status: status ?? this.status,
      release: release ?? this.release,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedApkPath: downloadedApkPath ?? this.downloadedApkPath,
      error: error,
    );
  }
}

final updateProvider = NotifierProvider<UpdateController, UpdateState>((ref) {
  return UpdateController();
});

class UpdateController extends Notifier<UpdateState> {
  @override
  UpdateState init() => const UpdateState(status: UpdateStatus.idle);

  /// Startup flow: silently checks, and when a new version is found (and has
  /// not been prompted before), downloads it and then navigates to the update page.
  Future<void> autoCheck() async {
    await _check();
    final release = state.release;
    if (state.status != UpdateStatus.available || release == null) {
      return;
    }
    final persistence = ref.read(persistenceProvider);
    if (persistence.getUpdatePromptedVersion() == release.version) {
      // The user already saw (and dismissed) this version.
      return;
    }
    await persistence.setUpdatePromptedVersion(release.version);
    final success = await downloadUpdate();
    if (success) {
      await ref.global.dispatchAsync(NavigateAction.push(const UpdatePage()));
    }
  }

  /// Manual check from the settings page. Returns true when an update is available.
  Future<bool> checkForUpdates() async {
    await _check();
    return state.status == UpdateStatus.available;
  }

  Future<void> _check() async {
    state = state.copyWith(status: UpdateStatus.checking, error: null);
    try {
      final version = await ref.future(versionProvider);
      final release = await _fetchLatestRelease();
      if (release == null) {
        state = state.copyWith(status: UpdateStatus.error, error: 'No release found');
        return;
      }
      if (!isNewerVersion(release.version, version.version)) {
        state = state.copyWith(status: UpdateStatus.upToDate, release: release);
        return;
      }
      state = state.copyWith(status: UpdateStatus.available, release: release);
    } catch (e) {
      state = state.copyWith(status: UpdateStatus.error, error: e);
    }
  }

  /// Downloads the APK of the current [ReleaseInfo]. Returns true on success.
  Future<bool> downloadUpdate() async {
    final release = state.release;
    if (release == null) {
      return false;
    }
    state = state.copyWith(status: UpdateStatus.downloading, downloadProgress: 0, error: null);
    try {
      final file = File(await _apkTargetPath(release));
      if (await file.exists()) {
        await file.delete();
      }
      await file.parent.create(recursive: true);

      final client = http.Client();
      final response = await client.send(http.Request('GET', Uri.parse(release.apkUrl)));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? release.apkSize;
      int received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) {
            state = state.copyWith(downloadProgress: received / total);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
        client.close();
      }
      state = state.copyWith(
        status: UpdateStatus.downloaded,
        downloadProgress: 1,
        downloadedApkPath: file.path,
      );
      return true;
    } catch (e) {
      state = state.copyWith(status: UpdateStatus.error, error: e);
      return false;
    }
  }

  Future<String> _apkTargetPath(ReleaseInfo release) async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}${Platform.pathSeparator}$kReleaseAssetPrefix${release.version}.apk';
  }

  Future<ReleaseInfo?> _fetchLatestRelease() async {
    final uri = Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest');
    final response = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'localsend-x-update-check',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('GitHub API returned HTTP ${response.statusCode}');
    }

    final dynamic json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map || json['tag_name'] is! String) {
      return null;
    }
    final tagName = json['tag_name'] as String;
    final version = tagName.replaceFirst(RegExp('^v'), '');

    final apkUrl = await _pickApkUrl(json);
    if (apkUrl == null) {
      return null;
    }

    return ReleaseInfo(
      tagName: tagName,
      version: version,
      changelog: json['body'] is String ? json['body'] as String : null,
      apkUrl: apkUrl,
      apkSize: _pickApkSize(json, apkUrl),
    );
  }

  /// Picks the release asset matching the device ABI. Falls back to the
  /// 64-bit ARM APK when the ABI detection fails, so that at least a
  /// download is possible.
  Future<String?> _pickApkUrl(Map<dynamic, dynamic> json) async {
    final assets = json['assets'];
    if (assets is! List) {
      return null;
    }
    List<String> abis;
    try {
      abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    } catch (_) {
      abis = const ['arm64-v8a'];
    }

    String? arm64Fallback;
    for (final asset in assets) {
      if (asset is! Map || asset['browser_download_url'] is! String) {
        continue;
      }
      final url = asset['browser_download_url'] as String;
      final fileName = url.split('/').last;
      if (!fileName.startsWith(kReleaseAssetPrefix) || !fileName.endsWith('.apk')) {
        continue;
      }
      for (final abi in abis) {
        final suffix = releaseAssetSuffixForAbi(abi);
        if (suffix != null && fileName.endsWith('android-$suffix.apk')) {
          return url;
        }
      }
      if (fileName.endsWith('android-arm64v8.apk')) {
        arm64Fallback = url;
      }
    }
    return arm64Fallback;
  }

  int _pickApkSize(Map<dynamic, dynamic> json, String apkUrl) {
    final assets = json['assets'];
    if (assets is! List) {
      return 0;
    }
    for (final asset in assets) {
      if (asset is Map && asset['browser_download_url'] == apkUrl) {
        final size = asset['size'];
        if (size is int) {
          return size;
        }
      }
    }
    return 0;
  }
}

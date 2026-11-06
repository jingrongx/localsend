// Pure helpers for the in-app update mechanism.

/// Parses a version string like "1.2.3" (a leading "v" is ignored) into
/// numeric parts. Returns null when the string is not a plain version.
List<int>? parseVersion(String version) {
  final normalized = version.trim().replaceFirst(RegExp('^v'), '');
  final parts = normalized.split('.');
  if (parts.isEmpty || parts.length > 3) {
    return null;
  }
  final numbers = <int>[];
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || part.isEmpty) {
      return null;
    }
    numbers.add(number);
  }
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers;
}

/// Returns true when [remote] (from a GitHub release tag) is strictly newer
/// than [current] (from package info). Unknown formats are never "newer".
bool isNewerVersion(String remote, String current) {
  final remoteParts = parseVersion(remote);
  final currentParts = parseVersion(current);
  if (remoteParts == null || currentParts == null) {
    return false;
  }
  for (int i = 0; i < 3; i++) {
    if (remoteParts[i] != currentParts[i]) {
      return remoteParts[i] > currentParts[i];
    }
  }
  return false;
}

/// The asset suffix in the release APK file names, e.g. "arm64v8" in
/// "LocalSendX-1.2.3-android-arm64v8.apk".
String? releaseAssetSuffixForAbi(String abi) {
  switch (abi) {
    case 'arm64-v8a':
      return 'arm64v8';
    case 'armeabi-v7a':
      return 'arm32v7';
    case 'x86_64':
      return 'x64';
    default:
      return null;
  }
}

/// Picks the release asset download URL for the first supported ABI of the
/// device. Returns null when the release has no matching APK.
String? releaseApkUrlForAbis(List<String> supportedAbis, Iterable<MapEntry<String, String>> assets) {
  for (final abi in supportedAbis) {
    final suffix = releaseAssetSuffixForAbi(abi);
    if (suffix == null) {
      continue;
    }
    for (final asset in assets) {
      if (asset.key.endsWith('android-$suffix.apk')) {
        return asset.value;
      }
    }
  }
  return null;
}

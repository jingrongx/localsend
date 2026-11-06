import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/update/update_utils.dart';

void main() {
  group('parseVersion', () {
    test('parses two and three part versions, ignoring a leading v', () {
      expect(parseVersion('v1.2.3'), [1, 2, 3]);
      expect(parseVersion('1.2'), [1, 2, 0]);
      expect(parseVersion(' 2.0.1 '), [2, 0, 1]);
    });

    test('rejects unknown formats', () {
      expect(parseVersion('1.2.3.4'), null);
      expect(parseVersion('1.2.3+64'), null);
      expect(parseVersion('beta'), null);
      expect(parseVersion(''), null);
    });
  });

  group('isNewerVersion', () {
    test('compares numerically, not lexicographically', () {
      expect(isNewerVersion('1.10.0', '1.9.0'), true);
      expect(isNewerVersion('1.0.1', '1.0.0'), true);
      expect(isNewerVersion('2.0.0', '1.9.9'), true);
    });

    test('same or older versions are not newer', () {
      expect(isNewerVersion('1.0.0', '1.0.0'), false);
      expect(isNewerVersion('1.0.0', '1.0.1'), false);
      expect(isNewerVersion('v1.0.0', '1.0.0'), false);
    });

    test('unknown formats never count as newer', () {
      expect(isNewerVersion('beta', '1.0.0'), false);
      expect(isNewerVersion('1.0.0', 'unknown'), false);
    });
  });

  group('releaseAssetSuffixForAbi', () {
    test('maps the supported ABIs to the release asset suffixes', () {
      expect(releaseAssetSuffixForAbi('arm64-v8a'), 'arm64v8');
      expect(releaseAssetSuffixForAbi('armeabi-v7a'), 'arm32v7');
      expect(releaseAssetSuffixForAbi('x86_64'), 'x64');
      expect(releaseAssetSuffixForAbi('mips'), null);
    });
  });

  group('releaseApkUrlForAbis', () {
    const assets = [
      MapEntry('LocalSendX-1.2.3-android-arm32v7.apk', 'https://example.com/arm32'),
      MapEntry('LocalSendX-1.2.3-android-arm64v8.apk', 'https://example.com/arm64'),
      MapEntry('LocalSendX-1.2.3-android-x64.apk', 'https://example.com/x64'),
    ];

    test('prefers the first matching supported ABI', () {
      expect(
        releaseApkUrlForAbis(['arm64-v8a', 'armeabi-v7a'], assets),
        'https://example.com/arm64',
      );
      expect(
        releaseApkUrlForAbis(['armeabi-v7a', 'arm64-v8a'], assets),
        'https://example.com/arm32',
      );
    });

    test('falls back to later ABIs when an asset is missing', () {
      final partialAssets = assets.where((e) => e.key.contains('arm64')).toList();
      expect(
        releaseApkUrlForAbis(['x86_64', 'arm64-v8a'], partialAssets),
        'https://example.com/arm64',
      );
    });

    test('returns null when nothing matches', () {
      expect(releaseApkUrlForAbis(['mips'], assets), null);
    });
  });
}

import 'package:astra/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isVersionNewer', () {
    test('detects newer patch, minor and major versions', () {
      expect(isVersionNewer('2.0.0', '2.0.1'), isTrue);
      expect(isVersionNewer('2.0.0', '2.1.0'), isTrue);
      expect(isVersionNewer('2.0.0', '3.0.0'), isTrue);
    });

    test('returns false for the same or an older version', () {
      expect(isVersionNewer('2.0.0', '2.0.0'), isFalse);
      expect(isVersionNewer('2.0.0', '1.9.9'), isFalse);
    });

    test('ignores the v prefix and build metadata', () {
      expect(isVersionNewer('2.0.0+2', 'v2.0.1'), isTrue);
      expect(normalizeVersion('v2.0.0'), '2.0.0');
      expect(isVersionNewer('2.0.0', '2.0.0-beta'), isFalse);
    });

    test('handles different segment lengths', () {
      expect(isVersionNewer('2.0', '2.0.1'), isTrue);
      expect(isVersionNewer('2.0.1', '2.0'), isFalse);
    });
  });

  test('UpdateInfo compares against the running version', () {
    const info = UpdateInfo(
      latestVersion: '2.2.0',
      releaseUrl: 'https://example.com/releases',
    );
    expect(info.isNewerThan('2.0.0'), isTrue);
    expect(info.isNewerThan('2.2.0'), isFalse);
  });
}

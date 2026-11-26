import 'dart:convert';
import 'dart:io';

class UpdateInfo {
  final String latestVersion;
  final String releaseUrl;
  final String releaseNotes;

  const UpdateInfo({
    required this.latestVersion,
    required this.releaseUrl,
    this.releaseNotes = '',
  });

  bool isNewerThan(String currentVersion) =>
      isVersionNewer(currentVersion, latestVersion);
}

/// Checks GitHub Releases for a newer desktop build.
class UpdateService {
  static const String repoUrl = 'https://github.com/compiler-says-no/astra';
  static const String documentationUrl = '$repoUrl#readme';
  static const String supportUrl = '$repoUrl/issues';
  static const String releasesApi =
      'https://api.github.com/repos/compiler-says-no/astra/releases/latest';

  Future<UpdateInfo?> checkForUpdates({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse(releasesApi))
          .timeout(timeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'astra-desktop');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub returned HTTP ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').trim();
      return UpdateInfo(
        latestVersion: normalizeVersion(tag),
        releaseUrl: json['html_url'] as String? ?? '$repoUrl/releases',
        releaseNotes: json['body'] as String? ?? '',
      );
    } finally {
      client.close(force: true);
    }
  }
}

String normalizeVersion(String value) {
  var version = value.trim();
  if (version.startsWith('v') || version.startsWith('V')) {
    version = version.substring(1);
  }
  return version;
}

/// Returns true when [latest] is semantically greater than [current].
bool isVersionNewer(String current, String latest) {
  final currentParts = _parts(current);
  final latestParts = _parts(latest);
  final length = currentParts.length > latestParts.length
      ? currentParts.length
      : latestParts.length;
  for (var index = 0; index < length; index++) {
    final a = index < currentParts.length ? currentParts[index] : 0;
    final b = index < latestParts.length ? latestParts[index] : 0;
    if (a != b) return b > a;
  }
  return false;
}

List<int> _parts(String value) {
  final normalized = normalizeVersion(value).split('+').first;
  return normalized.split('.').map((part) {
    final match = RegExp(r'^\d+').firstMatch(part);
    return match == null ? 0 : int.parse(match.group(0)!);
  }).toList();
}

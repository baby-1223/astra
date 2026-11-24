import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 凭据以该前缀写入 workspace，真实值保存在系统凭据库。
const String secretMarker = 'secure:';

const List<String> _secretFields = [
  'token',
  'password',
  'apiKeyValue',
  'oauthClientSecret',
  'oauthRefreshToken',
];

abstract class SecretStore {
  Future<void> write(String ref, String value);
  Future<String?> read(String ref);
  Future<void> delete(String ref);
}

/// macOS Keychain / Windows Credential Manager 实现。
///
/// macOS 上使用 legacy keychain（不使用 data protection keychain），这样无需
/// `keychain-access-groups` entitlement，本地构建也不需要开发证书签名。
class KeychainSecretStore implements SecretStore {
  KeychainSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  static const String _prefix = 'astra.secret.';
  final FlutterSecureStorage _storage;
  final Map<String, String> _cache = {};

  @override
  Future<void> write(String ref, String value) async {
    if (_cache[ref] == value) return;
    await _storage.write(key: '$_prefix$ref', value: value);
    _cache[ref] = value;
  }

  @override
  Future<String?> read(String ref) async {
    final cached = _cache[ref];
    if (cached != null) return cached;
    final value = await _storage.read(key: '$_prefix$ref');
    if (value != null) _cache[ref] = value;
    return value;
  }

  @override
  Future<void> delete(String ref) async {
    _cache.remove(ref);
    await _storage.delete(key: '$_prefix$ref');
  }
}

/// 测试用内存实现。
class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<void> write(String ref, String value) async {
    values[ref] = value;
  }

  @override
  Future<String?> read(String ref) async => values[ref];

  @override
  Future<void> delete(String ref) async {
    values.remove(ref);
  }
}

/// 删除指定请求在凭据库中的所有凭据，重置工作区时调用。
Future<void> forgetRequestSecrets(
  Iterable<String> requestIds,
  SecretStore store,
) async {
  for (final id in requestIds.toSet()) {
    for (final field in _secretFields) {
      try {
        await store.delete(secretRef(id, field));
      } catch (_) {
        // 删除失败不影响重置流程。
      }
    }
  }
}

String secretRef(String requestId, String field) => 'request/$requestId/$field';

/// 把请求凭据替换为占位符，并写入系统凭据库；返回可直接落盘的新 Map。
/// 凭据库写入失败时保留明文，避免丢数据。
Future<Map<String, dynamic>> redactSecrets(
  Map<String, dynamic> data,
  SecretStore store,
) async {
  final copy = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  await _walk(copy, (auth, requestId) async {
    for (final field in _secretFields) {
      final value = auth[field];
      if (value is! String || value.isEmpty || value.startsWith(secretMarker)) {
        continue;
      }
      final ref = secretRef(requestId, field);
      try {
        await store.write(ref, value);
        auth[field] = '$secretMarker$ref';
      } catch (_) {
        // 写入失败保留明文，至少不丢数据。
      }
    }
  });
  return copy;
}

/// 把占位符替换回真实凭据；读取失败时保留占位符，不做破坏性清空。
Future<void> hydrateSecrets(Map<String, dynamic> data, SecretStore store) async {
  await _walk(data, (auth, requestId) async {
    for (final field in _secretFields) {
      final value = auth[field];
      if (value is! String || !value.startsWith(secretMarker)) continue;
      final ref = value.substring(secretMarker.length);
      final resolved = await store.read(ref);
      if (resolved != null) auth[field] = resolved;
    }
  });
}

Future<void> _walk(
  dynamic node,
  Future<void> Function(Map<String, dynamic> auth, String ownerId) visit, {
  String ownerId = 'root',
}) async {
  if (node is Map) {
    final id = node['id'];
    final currentId = id is String ? id : ownerId;
    final auth = node['auth'];
    if (auth is Map<String, dynamic>) {
      await visit(auth, currentId);
    }
    for (final value in List.of(node.values)) {
      await _walk(value, visit, ownerId: currentId);
    }
  } else if (node is List) {
    for (var index = 0; index < node.length; index++) {
      await _walk(node[index], visit, ownerId: '$ownerId/$index');
    }
  }
}

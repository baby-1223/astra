import 'package:astra/state.dart';
import 'package:astra/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingSecretStore implements SecretStore {
  @override
  Future<void> write(String ref, String value) async => throw Exception('locked');

  @override
  Future<String?> read(String ref) async => null;

  @override
  Future<void> delete(String ref) async {}
}

void main() {
  group('凭据安全存储', () {
    test('持久化时替换为占位符，加载时还原', () async {
      final store = MemorySecretStore();
      final data = {
        'collections': [
          {
            'id': 'req-1',
            'name': '登录',
            'auth': {
              'type': 'bearer',
              'token': 'token-value',
              'password': 'pass-value',
            },
          },
        ],
      };

      final redacted = await redactSecrets(data, store);
      final auth = (redacted['collections'] as List).first['auth'];
      expect(auth['token'], 'secure:request/req-1/token');
      expect(auth['password'], 'secure:request/req-1/password');
      expect(store.values['request/req-1/token'], 'token-value');

      // 原始内存数据不受影响。
      expect((data['collections'] as List).first['auth']['token'], 'token-value');

      await hydrateSecrets(redacted, store);
      expect(auth['token'], 'token-value');
      expect(auth['password'], 'pass-value');
    });

    test('凭据库不可用时保留明文', () async {
      final data = {
        'collections': [
          {
            'id': 'req-2',
            'auth': {'type': 'apikey', 'apiKeyValue': 'key-value'},
          },
        ],
      };

      final redacted = await redactSecrets(data, FailingSecretStore());
      final auth = (redacted['collections'] as List).first['auth'];
      expect(auth['apiKeyValue'], 'key-value');
    });

    test('历史快照中的凭据也会被替换', () async {
      final store = MemorySecretStore();
      final data = {
        'history': [
          {
            'id': 'h-1',
            'request': {
              'id': 'req-3',
              'auth': {'type': 'bearer', 'token': 'history-token'},
            },
          },
        ],
      };

      final redacted = await redactSecrets(data, store);
      final request = (redacted['history'] as List).first['request'];
      expect(request['auth']['token'], 'secure:request/req-3/token');
      expect(store.values['request/req-3/token'], 'history-token');
    });

    test('读取不到时保留占位符，不清空引用', () async {
      final data = {
        'collections': [
          {
            'id': 'req-4',
            'auth': {'type': 'bearer', 'token': 'secure:request/req-4/token'},
          },
        ],
      };

      await hydrateSecrets(data, MemorySecretStore());
      final auth = (data['collections'] as List).first['auth'];
      expect(auth['token'], 'secure:request/req-4/token');
    });
  });

  group('工作区版本', () {
    test('导出文件带 schemaVersion', () {
      final state = AppState();
      expect(state.exportAstra()['schemaVersion'], AppState.workspaceSchemaVersion);
      expect(state.exportAstra()['app'], 'Astra');
    });
  });
}

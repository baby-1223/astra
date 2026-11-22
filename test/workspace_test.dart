import 'package:astra/models.dart';
import 'package:astra/services/ws_service.dart';
import 'package:astra/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('多环境', () {
    test('创建、切换与删除环境', () {
      final state = AppState();
      final dev = state.createEnv('开发');
      state.updateEnvById(dev.id, '开发', [KV(k: 'host', v: 'http://dev.local')]);
      final prod = state.createEnv('生产');
      state.updateEnvById(prod.id, '生产', [KV(k: 'host', v: 'http://prod.local')]);

      expect(state.env.name, '生产');
      state.switchEnv(dev.id);
      expect(state.env.name, '开发');
      expect(state.resolve('{{host}}/api'), 'http://dev.local/api');

      expect(state.deleteEnv(dev.id), isTrue);
      expect(state.env.id, state.environments.first.id);
      // 至少保留一个环境
      state.deleteEnv(state.environments[1].id);
      expect(state.deleteEnv(state.environments.first.id), isFalse);
      expect(state.environments.length, 1);
    });

    test('复制环境不会共享变量列表', () {
      final state = AppState();
      final source = state.env;
      state.updateEnvById(source.id, '开发', [KV(k: 'token', v: 'abc')]);
      state.duplicateEnv(source.id);

      final copy = state.env;
      expect(copy.name, '开发 copy');
      expect(copy.vars.single.v, 'abc');
      copy.vars.first.v = 'changed';
      expect(state.environments.first.vars.first.v, 'abc');
    });

    test('变量解析优先使用当前环境', () {
      final state = AppState();
      final dev = state.createEnv('开发');
      state.updateEnvById(dev.id, '开发', [KV(k: 'env', v: 'dev')]);
      final prod = state.createEnv('生产');
      state.updateEnvById(prod.id, '生产', [KV(k: 'env', v: 'prod')]);

      expect(state.resolve('{{env}}'), 'prod');
      state.switchEnv(dev.id);
      expect(state.resolve('{{env}}'), 'dev');
    });
  });

  group('集合分组', () {
    test('HTTP 请求按集合归档', () {
      final state = AppState();
      state.request = ApiRequest(method: 'POST', url: 'https://api.demo.com/users');
      final group = state.createGroup('用户服务', 'http');
      state.saveCurrent('创建用户', groupId: group.id);

      expect(state.collections.single.groupId, group.id);
      expect(state.entriesFor('http').length, 1);
      expect(state.entriesFor('ws'), isEmpty);
      expect(state.groupsFor('http').single.name, '用户服务');
      expect(state.groupsFor('ws'), isEmpty);
    });

    test('删除集合后条目与文件夹均被删除', () {
      final state = AppState();
      state.request = ApiRequest(url: 'https://api.demo.com/users');
      final group = state.createGroup('用户服务', 'http');
      final folder = state.createFolder(group.id, '', '管理端');
      state.saveCurrent('用户列表', groupId: group.id, folderId: folder.id);

      state.deleteGroup(group.id);
      expect(state.groups, isEmpty);
      expect(state.folders, isEmpty);
      expect(state.collections, isEmpty);
    });

    test('WebSocket 连接保存到连接集合', () {
      final state = AppState();
      state.mode = 'ws';
      state.ws = WsConfig(url: 'ws://127.0.0.1:8080/ws');
      final group = state.createGroup('实时通道', 'ws');
      state.saveCurrent('本地回显', groupId: group.id);

      final entry = state.collections.single;
      expect(entry.mode, 'ws');
      expect(entry.groupId, group.id);
      expect(state.entriesFor('ws').single.ws?.url, 'ws://127.0.0.1:8080/ws');
      expect(state.entriesFor('http'), isEmpty);
    });

    test('集合折叠状态可切换', () {
      final state = AppState();
      final group = state.createGroup('用户服务', 'http');
      expect(group.expanded, isTrue);
      state.toggleGroup(group.id);
      expect(state.groups.single.expanded, isFalse);
    });
  });

  group('集合内文件夹', () {
    test('支持多级文件夹嵌套', () {
      final state = AppState();
      final group = state.createGroup('用户服务', 'http');
      final level1 = state.createFolder(group.id, '', '管理端');
      final level2 = state.createFolder(group.id, level1.id, '用户管理');
      final level3 = state.createFolder(group.id, level2.id, '详情');

      expect(state.rootFolders(group.id).single.name, '管理端');
      expect(state.childFolders(level1.id).single.name, '用户管理');
      expect(state.childFolders(level2.id).single.name, '详情');
      expect(state.folderPath(level3.id), '管理端 / 用户管理 / 详情');
    });

    test('请求可保存到文件夹', () {
      final state = AppState();
      state.request = ApiRequest(url: 'https://api.demo.com/users');
      final group = state.createGroup('用户服务', 'http');
      final folder = state.createFolder(group.id, '', '管理端');
      state.saveCurrent('用户列表', groupId: group.id, folderId: folder.id);

      final entry = state.collections.single;
      expect(entry.groupId, group.id);
      expect(entry.folderId, folder.id);
      expect(state.entriesInFolder(folder.id).single.name, '用户列表');
      expect(state.entriesInGroupRoot(group.id), isEmpty);
    });

    test('删除文件夹会删除其内容与子文件夹', () {
      final state = AppState();
      state.request = ApiRequest(url: 'https://api.demo.com/users');
      final group = state.createGroup('用户服务', 'http');
      final parent = state.createFolder(group.id, '', '管理端');
      final child = state.createFolder(group.id, parent.id, '用户管理');
      state.saveCurrent('用户列表', groupId: group.id, folderId: child.id);

      state.deleteFolder(parent.id);

      expect(state.folders, isEmpty);
      expect(state.collections, isEmpty);
    });

    test('删除集合会一并删除其文件夹', () {
      final state = AppState();
      final group = state.createGroup('用户服务', 'http');
      state.createFolder(group.id, '', '管理端');
      state.deleteGroup(group.id);
      expect(state.folders, isEmpty);
    });
  });

  group('备份', () {
    test('导出内容包含全部环境、集合与文件夹', () {
      final state = AppState();
      state.createEnv('测试');
      final group = state.createGroup('用户服务', 'http');
      state.createFolder(group.id, '', '管理端');
      state.createGroup('实时通道', 'ws');

      final data = state.exportAstra();
      expect((data['environments'] as List).length, 2);
      expect((data['groups'] as List).length, 2);
      expect((data['folders'] as List).length, 1);
      expect(data['activeEnvId'], state.activeEnvId);
    });
  });

  group('历史记录', () {
    test('历史按 Session 隔离', () {
      final state = AppState();
      state.history.add(HistoryEntry(mode: 'http', method: 'GET', url: 'https://a.com'));
      state.history.add(HistoryEntry(mode: 'ws', method: 'WS', url: 'ws://b.com'));
      state.history.add(HistoryEntry(mode: 'http', method: 'POST', url: 'https://c.com'));

      expect(state.historyFor('http').length, 2);
      expect(state.historyFor('ws').length, 1);
    });

    test('删除单条历史记录', () {
      final state = AppState();
      final a = HistoryEntry(mode: 'http', method: 'GET', url: 'https://a.com');
      final b = HistoryEntry(mode: 'http', method: 'GET', url: 'https://b.com');
      state.history.addAll([a, b]);

      state.deleteHistoryEntry(a.id);
      expect(state.history.length, 1);
      expect(state.history.single.id, b.id);
    });

    test('批量删除多条历史记录', () {
      final state = AppState();
      final a = HistoryEntry(mode: 'http', method: 'GET', url: 'https://a.com');
      final b = HistoryEntry(mode: 'http', method: 'GET', url: 'https://b.com');
      final c = HistoryEntry(mode: 'http', method: 'GET', url: 'https://c.com');
      state.history.addAll([a, b, c]);

      state.deleteHistoryEntries({a.id, c.id});
      expect(state.history.length, 1);
      expect(state.history.single.id, b.id);
    });

    test('清空当前 Session 的历史记录', () {
      final state = AppState();
      state.history.addAll([
        HistoryEntry(mode: 'http', method: 'GET', url: 'https://a.com'),
        HistoryEntry(mode: 'ws', method: 'WS', url: 'ws://b.com'),
      ]);

      final ids = state.historyFor('http').map((item) => item.id).toSet();
      state.deleteHistoryEntries(ids);

      expect(state.historyFor('http'), isEmpty);
      expect(state.historyFor('ws').length, 1);
    });
  });

  group('WebSocket 历史记录', () {
    test('HistoryEntry 序列化保留 wsSnapshot', () {
      final entry = HistoryEntry(
        mode: 'ws',
        method: 'WS',
        url: 'ws://demo.local/ws',
        status: 101,
        ms: 33,
        wsSnapshot: WsConfig(
          url: 'ws://demo.local/ws',
          subprotocol: 'graphql-ws',
          verify: false,
          headers: [KV(k: 'X-Token', v: 'abc', on: true)],
        ),
      );

      final restored = HistoryEntry.fromJson(entry.toJson());
      expect(restored.mode, 'ws');
      expect(restored.method, 'WS');
      expect(restored.status, 101);
      expect(restored.wsSnapshot, isNotNull);
      expect(restored.wsSnapshot!.url, 'ws://demo.local/ws');
      expect(restored.wsSnapshot!.subprotocol, 'graphql-ws');
      expect(restored.wsSnapshot!.verify, false);
      expect(restored.wsSnapshot!.headers.single.k, 'X-Token');
    });

    test('打开 WS 历史会以 WebSocket 标签页恢复配置', () {
      final state = AppState()..switchMode('ws');
      final entry = HistoryEntry(
        mode: 'ws',
        method: 'WS',
        url: 'ws://demo.local/ws',
        wsSnapshot: WsConfig(url: 'ws://demo.local/ws', subprotocol: 'json'),
      );

      state.openHistory(entry);

      expect(state.mode, 'ws');
      expect(state.activeTab, isNotNull);
      expect(state.activeTab!.mode, 'ws');
      expect(state.ws.url, 'ws://demo.local/ws');
      expect(state.ws.subprotocol, 'json');
    });

    test('连接成功会记录一条 WS 历史', () async {
      final fake = _FakeWsService(throwOnConnect: false);
      final state = AppState(wsService: fake)..switchMode('ws');
      state.ws.url = 'ws://demo.local/ws';

      await state.connectWs();

      expect(state.history.length, 1);
      final entry = state.history.first;
      expect(entry.mode, 'ws');
      expect(entry.method, 'WS');
      expect(entry.url, 'ws://demo.local/ws');
      expect(entry.status, 101);
      expect(entry.wsSnapshot, isNotNull);
    });

    test('连接失败也会记录一条 WS 历史（status 为空）', () async {
      final fake = _FakeWsService(throwOnConnect: true);
      final state = AppState(wsService: fake)..switchMode('ws');
      state.ws.url = 'ws://unreachable.local/ws';

      await state.connectWs();

      expect(state.history.length, 1);
      final entry = state.history.first;
      expect(entry.mode, 'ws');
      expect(entry.status, isNull);
      expect(entry.url, 'ws://unreachable.local/ws');
    });
  });

  group('cURL 互转', () {
    test('解析 POST JSON 请求', () {
      final state = AppState();
      final req = state.parseCurl(
        "curl -X POST 'https://api.demo.com/users' \\\n"
        "  -H 'Content-Type: application/json' \\\n"
        "  -H 'X-Token: abc' \\\n"
        "  -d '{\"name\":\"astra\"}'",
      );

      expect(req.method, 'POST');
      expect(req.url, 'https://api.demo.com/users');
      expect(req.headers.where((item) => item.k.isNotEmpty).length, 2);
      expect(req.headers.firstWhere((item) => item.k == 'X-Token').v, 'abc');
      expect(req.bodyMode, 'json');
      expect(req.body, '{"name":"astra"}');
    });

    test('解析 -u 基本认证与 -F 表单上传', () {
      final state = AppState();
      final req = state.parseCurl(
        "curl 'https://api.demo.com/upload' -u 'demo:secret' -F 'file=@/tmp/a.png' -F 'name=astra'",
      );

      expect(req.auth.type, 'basic');
      expect(req.auth.username, 'demo');
      expect(req.auth.password, 'secret');
      expect(req.bodyMode, 'form-data');
      expect(req.formData.where((row) => row.type == 'file').length, 1);
      expect(req.formData.firstWhere((row) => row.k == 'name').v, 'astra');
    });

    test('导出后可再次解析且信息一致', () {
      final state = AppState();
      final source = ApiRequest(
        method: 'PUT',
        url: 'https://api.demo.com/items',
        headers: [KV(on: true, k: 'X-Trace', v: '1')],
        bodyMode: 'json',
        body: '{"ok":true}',
      );

      final curl = state.curlFor(source);
      expect(curl, contains('curl -X PUT'));
      expect(curl, contains('-H'));
      expect(curl, contains('--data-raw'));

      final parsed = state.parseCurl(curl);
      expect(parsed.method, 'PUT');
      expect(parsed.url, 'https://api.demo.com/items');
      expect(parsed.headers.firstWhere((item) => item.k == 'X-Trace').v, '1');
      expect(parsed.body, '{"ok":true}');
    });

    test('无效内容抛出 FormatException', () {
      final state = AppState();
      expect(() => state.parseCurl('not a curl'), throwsFormatException);
      expect(() => state.parseCurl('curl -X GET'), throwsFormatException);
    });

    test('openCurl 会新建请求标签页', () {
      final state = AppState()..switchMode('ws');
      state.openCurl("curl 'https://api.demo.com/ping'");

      expect(state.mode, 'http');
      expect(state.activeTab, isNotNull);
      expect(state.request.url, 'https://api.demo.com/ping');
    });
  });

  group('认证与超时', () {
    test('API Key 可注入 Header', () {
      final state = AppState();
      final req = ApiRequest(url: 'https://api.demo.com/users');
      req.auth
        ..type = 'apikey'
        ..apiKeyName = 'X-API-Key'
        ..apiKeyValue = 'k-123'
        ..apiKeyIn = 'header';

      expect(state.collectHeaders(req)['X-API-Key'], 'k-123');
      expect(state.buildUrl(req), 'https://api.demo.com/users');
    });

    test('API Key 可注入 Query 参数', () {
      final state = AppState();
      final req = ApiRequest(url: 'https://api.demo.com/users');
      req.auth
        ..type = 'apikey'
        ..apiKeyName = 'api_key'
        ..apiKeyValue = 'k-123'
        ..apiKeyIn = 'query';

      expect(state.buildUrl(req), 'https://api.demo.com/users?api_key=k-123');
      expect(state.collectHeaders(req).containsKey('api_key'), isFalse);
    });

    test('OAuth2 与超时配置可序列化', () {
      final req = ApiRequest();
      req.auth
        ..type = 'oauth2'
        ..token = 'access-abc'
        ..oauthTokenUrl = 'https://api.demo.com/oauth/token'
        ..oauthClientId = 'client'
        ..oauthGrantType = 'password';
      req.options.timeoutSeconds = 15;

      final restored = ApiRequest.fromJson(req.toJson());
      expect(restored.auth.type, 'oauth2');
      expect(restored.auth.token, 'access-abc');
      expect(restored.auth.oauthTokenUrl, 'https://api.demo.com/oauth/token');
      expect(restored.auth.oauthGrantType, 'password');
      expect(restored.options.timeoutSeconds, 15);
      expect(restored.auth.password, '');
    });

    test('OAuth2 Token 作为 Bearer 注入 Header', () {
      final state = AppState();
      final req = ApiRequest(url: 'https://api.demo.com/users');
      req.auth
        ..type = 'oauth2'
        ..token = 'access-abc';

      expect(state.collectHeaders(req)['Authorization'], 'Bearer access-abc');
    });
  });
}

/// 可配置行为的假 WebSocket 服务，用于单元测试
class _FakeWsService extends WsService {
  final bool throwOnConnect;
  _FakeWsService({required this.throwOnConnect});

  @override
  Future<void> connect({
    required String url,
    required Map<String, String> headers,
    required String subprotocol,
    required bool verify,
    required void Function() onOpen,
    required void Function(dynamic data) onMessage,
    required void Function(String reason) onClose,
    required void Function(String message) onError,
  }) async {
    if (throwOnConnect) {
      throw Exception('连接失败：refused');
    }
    onOpen();
  }

  @override
  Future<void> close() async {}

  @override
  void send(String text) {}
}

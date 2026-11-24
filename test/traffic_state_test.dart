import 'dart:io';

import 'package:astra/models.dart';
import 'package:astra/services/capture_proxy.dart';
import 'package:astra/services/storage.dart';
import 'package:astra/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mock 配置序列化', () {
    test('包含端口、路由、响应头与延迟的往返', () {
      final config = MockServerConfig(
        port: 7001,
        routes: [
          MockRoute(
            id: 'r1',
            name: '订单详情',
            method: 'post',
            path: '/orders/:id',
            status: 201,
            body: '{"ok":true}',
            headers: [KV(k: 'x-trace', v: 'abc')],
            delayMs: 250,
            sourceEntryId: 'e1',
            ts: 1234,
          ),
        ],
      );

      final restored = MockServerConfig.fromJson(config.toJson());

      expect(restored.port, 7001);
      expect(restored.routes.single.id, 'r1');
      expect(restored.routes.single.name, '订单详情');
      expect(restored.routes.single.method, 'POST');
      expect(restored.routes.single.path, '/orders/:id');
      expect(restored.routes.single.status, 201);
      expect(restored.routes.single.body, '{"ok":true}');
      expect(restored.routes.single.headers.single.k, 'x-trace');
      expect(restored.routes.single.delayMs, 250);
      expect(restored.routes.single.sourceEntryId, 'e1');
      expect(restored.routes.single.ts, 1234);
    });

    test('缺失字段回落到默认值', () {
      final config = MockServerConfig.fromJson(const <String, dynamic>{});
      expect(config.port, 6790);
      expect(config.routes, isEmpty);
    });

    test('copy 不共享路由和响应头', () {
      final config = MockServerConfig(
        routes: [MockRoute(name: 'a', headers: [KV(k: 'a', v: '1')])],
      );
      final copy = config.copy();
      copy.routes.first.name = 'b';
      copy.routes.first.headers.first.v = '2';
      expect(config.routes.first.name, 'a');
      expect(config.routes.first.headers.first.v, '1');
    });
  });

  group('AppState Mock 路由操作', () {
    test('新增、更新、启停、删除与端口校验', () {
      final state = AppState();
      final route = MockRoute(name: '用户列表', path: '/users');

      state.addMockRoute(route);
      expect(state.mockServer.routes.length, 1);

      final updated = route.copy()
        ..name = '用户列表 v2'
        ..status = 204;
      state.updateMockRoute(updated);
      expect(state.mockServer.routes.single.name, '用户列表 v2');
      expect(state.mockServer.routes.single.status, 204);

      state.toggleMockRoute(route.id, false);
      expect(state.mockServer.routes.single.enabled, isFalse);

      state.deleteMockRoute(route.id);
      expect(state.mockServer.routes, isEmpty);

      state.setMockPort(7010);
      expect(state.mockServer.port, 7010);
      state.setMockPort(-1);
      state.setMockPort(70000);
      expect(state.mockServer.port, 7010);
    });

    test('update 未命中时插入为新路由', () {
      final state = AppState();
      state.addMockRoute(MockRoute(name: 'a'));
      state.updateMockRoute(MockRoute(name: 'b'));
      expect(state.mockServer.routes.length, 2);
      expect(state.mockServer.routes.first.name, 'b');
    });
  });

  group('从请求生成 Mock 路由', () {
    test('优先使用第一个响应示例的状态、响应头和 body', () {
      final state = AppState();
      final entry = CollectionEntry(
        name: '创建订单',
        request: ApiRequest(
          method: 'POST',
          url: 'https://api.demo.com/v1/orders/42?draft=1',
        ),
        examples: [
          RequestExample(
            status: 201,
            body: '{"id":42}',
            headers: {
              'content-type': ['application/json'],
              'content-length': ['9'],
              'connection': ['keep-alive'],
            },
          ),
        ],
      );

      final route = state.mockRouteForEntry(entry);

      expect(route.name, '创建订单');
      expect(route.method, 'POST');
      expect(route.path, '/v1/orders/:id');
      expect(route.status, 201);
      expect(route.body, '{"id":42}');
      expect(route.headers.map((h) => h.k), ['content-type']);
      expect(route.sourceEntryId, entry.id);
    });

    test('没有示例时使用内置随机模板与 JSON 响应头', () {
      final state = AppState();
      final entry = CollectionEntry(
        name: '健康检查',
        request: ApiRequest(method: 'GET', url: '{{baseUrl}}/health'),
      );

      final route = state.mockRouteForEntry(entry);

      expect(route.status, 200);
      expect(route.body, kSampleMockBody);
      expect(route.headers.single.k, 'content-type');
      expect(route.headers.single.v, 'application/json');
    });

    test('从抓包记录生成路由并还原请求', () {
      final state = AppState();
      final record = CaptureRecord(
        id: 'c1',
        ts: 1,
        method: 'PUT',
        url: 'https://api.demo.com/items/7?x=1',
        host: 'api.demo.com',
        requestHeaders: {'content-type': 'application/json', 'x-req': '1'},
        requestBody: '{"name":"box"}',
        status: 422,
        responseBody: '{"error":"invalid"}',
      );

      final route = state.mockRouteForCapture(record);
      expect(route.name, 'PUT /items/7');
      expect(route.path, '/items/7');
      expect(route.status, 422);
      expect(route.body, '{"error":"invalid"}');

      final request = requestFromCapture(record);
      expect(request.method, 'PUT');
      expect(request.url, record.url);
      expect(request.bodyMode, 'json');
      expect(request.body, '{"name":"box"}');
      expect(request.headers.map((h) => h.k), containsAll(['content-type', 'x-req']));
    });

    test('CONNECT 记录生成 GET 路由且空路径回落为 /', () {
      final route = mockRouteFromCapture(
        CaptureRecord(
          id: 'c2',
          ts: 1,
          method: 'CONNECT',
          url: 'https://api.demo.com',
          host: 'api.demo.com',
        ),
      );
      expect(route.method, 'GET');
      expect(route.path, '/');
      expect(route.status, 200);
    });
  });

  group('工作区导入导出与持久化', () {
    test('备份包含 Mock 配置并可再次导入', () {
      final source = AppState();
      source.addMockRoute(
        MockRoute(id: 'mock-1', name: '回放', path: '/replay', status: 202),
      );
      source.setMockPort(7020);

      final dump = source.exportAstra();
      expect((dump['mockServer'] as Map)['port'], 7020);

      final target = AppState();
      final message = target.importData(dump);

      expect(message, contains('1 mock routes'));
      expect(target.mockServer.port, 7020);
      expect(target.mockServer.routes.single.id, 'mock-1');
      expect(target.mockServer.routes.single.status, 202);
    });

    test('重复导入按路由 id 覆盖而不是追加', () {
      final source = AppState();
      source.addMockRoute(MockRoute(id: 'mock-1', name: 'v1', path: '/a'));
      final dump = source.exportAstra();

      final target = AppState();
      target.addMockRoute(MockRoute(id: 'mock-1', name: 'old', path: '/old'));
      target.importData(dump);

      expect(target.mockServer.routes.length, 1);
      expect(target.mockServer.routes.single.name, 'v1');
    });

    test('mockServer 写入 Storage 后可重新读取', () async {
      final tempDir = await Directory.systemTemp.createTemp('astra-mock-store');
      try {
        final storage = Storage(root: tempDir);
        final config = MockServerConfig(
          port: 7030,
          routes: [MockRoute(id: 'persisted', name: '持久化', path: '/p')],
        );
        expect(await storage.write('workspace.json', {'mockServer': config.toJson()}), isTrue);

        final data = await storage.read('workspace.json');
        final restored = MockServerConfig.fromJson(
          Map<String, dynamic>.from(data!['mockServer'] as Map),
        );
        expect(restored.port, 7030);
        expect(restored.routes.single.id, 'persisted');
      } finally {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      }
    });

    test('未知格式抛出 FormatException', () {
      final state = AppState();
      expect(() => state.importData({'foo': 'bar'}), throwsFormatException);
    });
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:astra/models.dart';
import 'package:astra/services/mock_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('路由匹配', () {
    MockRoute route(String method, String path, {bool enabled = true}) => MockRoute(
          method: method,
          path: path,
          enabled: enabled,
        );

    test('静态路径按方法匹配', () {
      final routes = [route('GET', '/users')];
      final match = matchMockRoute(routes, 'GET', '/users');
      expect(match, isNotNull);
      expect(match!.route.path, '/users');
      expect(matchMockRoute(routes, 'POST', '/users'), isNull);
    });

    test('ANY 匹配任意方法', () {
      final routes = [route('ANY', '/ping')];
      expect(matchMockRoute(routes, 'DELETE', '/ping'), isNotNull);
    });

    test('路径参数被解码并回填', () {
      final routes = [route('GET', '/users/:id/orders/:orderId')];
      final match = matchMockRoute(routes, 'GET', '/users/42/orders/order%201');
      expect(match, isNotNull);
      expect(match!.pathParams['id'], '42');
      expect(match.pathParams['orderId'], 'order 1');
    });

    test('尾部通配保留剩余路径', () {
      final routes = [route('GET', '/assets/*')];
      final match = matchMockRoute(routes, 'GET', '/assets/css/app.css');
      expect(match, isNotNull);
      expect(match!.pathParams['rest'], 'css/app.css');
    });

    test('禁用路由不参与匹配', () {
      final routes = [route('GET', '/health', enabled: false)];
      expect(matchMockRoute(routes, 'GET', '/health'), isNull);
    });

    test('静态片段优先于参数', () {
      final routes = [
        route('GET', '/users/:id'),
        route('GET', '/users/me'),
      ];
      final match = matchMockRoute(routes, 'GET', '/users/me');
      expect(match!.route.path, '/users/me');
    });

    test('段数不一致不匹配', () {
      expect(matchMockRoute([route('GET', '/users')], 'GET', '/users/42'), isNull);
      expect(matchMockRoute([route('GET', '/users/:id')], 'GET', '/users'), isNull);
    });
  });

  group('URL 转 Mock 路径', () {
    test('数字段替换为 :id 并去掉查询串', () {
      expect(mockPathFromUrl('https://api.example.com/users/42?tab=posts'), '/users/:id');
    });

    test('根路径', () {
      expect(mockPathFromUrl('https://api.example.com'), '/');
      expect(mockPathFromUrl('not a url'), '/');
    });
  });

  group('模板渲染', () {
    test('路径参数、查询、请求头与 JSON body', () {
      final output = renderMockTemplate(
        '{{id}}|{{query.page}}|{{header.X-Trace}}|{{body.user.name}}|{{body.items.0.sku}}',
        MockTemplateContext(
          pathParams: {'id': '42'},
          query: {'page': '3'},
          headers: {'x-trace': 'abc'},
          body: jsonEncode({
            'user': {'name': 'Ada'},
            'items': [
              {'sku': 'A-1'}
            ],
          }),
        ),
      );
      expect(output, '42|3|abc|Ada|A-1');
    });

    test('未知占位符原样保留', () {
      expect(renderMockTemplate('{{unknown}}', MockTemplateContext()), '{{unknown}}');
    });

    test('随机 token 生成合理数据', () {
      final random = Random(7);
      final uuid = renderMockTemplate(r'{{$guid}}', MockTemplateContext(), random: random);
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(uuid), isTrue);
      final email = renderMockTemplate(r'{{$randomEmail}}', MockTemplateContext(), random: random);
      expect(email, contains('@example.com'));
      final boolText = renderMockTemplate(r'{{$randomBoolean}}', MockTemplateContext(), random: random);
      expect(boolText, anyOf('true', 'false'));
      final intText = renderMockTemplate(r'{{$randomInt}}', MockTemplateContext(), random: random);
      expect(int.tryParse(intText), isNotNull);
    });

    test('无效 JSON body 不抛异常', () {
      final output = renderMockTemplate(
        '{{body.x}}',
        MockTemplateContext(body: 'not json'),
      );
      expect(output, '');
    });
  });

  group('Mock Server 端到端', () {
    late MockServerService service;
    late HttpClient client;

    setUp(() {
      service = MockServerService();
      client = HttpClient()..findProxy = ((_) => 'DIRECT');
    });

    tearDown(() async {
      client.close(force: true);
      await service.stop();
    });

    Future<HttpClientResponse> send(String method, String path, {Object? body}) async {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${service.port}$path'));
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      return request.close();
    }

    test('按路由返回状态、响应头和模板数据', () async {
      final config = MockServerConfig(port: 0, routes: [
        MockRoute(
          method: 'POST',
          path: '/users/:id',
          status: 201,
          headers: [KV(k: 'x-mock', v: 'yes'), KV()],
          body: '{"id":"{{id}}","echo":"{{body.name}}","trace":"{{header.X-Trace}}"}',
        ),
      ]);
      expect(await service.start(config), isNull);
      expect(service.port, greaterThan(0));

      final request = await client.openUrl('POST', Uri.parse('http://127.0.0.1:${service.port}/users/7'));
      request.headers.contentType = ContentType.json;
      request.headers.set('x-trace', 'trace-1');
      request.write(jsonEncode({'name': 'Ada'}));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();

      expect(response.statusCode, 201);
      expect(response.headers.value('x-mock'), 'yes');
      expect(response.headers.value('access-control-allow-origin'), '*');
      expect(jsonDecode(text), {'id': '7', 'echo': 'Ada', 'trace': 'trace-1'});
      expect(service.hits.single.matched, isTrue);
      expect(service.hits.single.status, 201);
    });

    test('未匹配返回 404 并列出可用路由', () async {
      final config = MockServerConfig(port: 0, routes: [MockRoute(path: '/health')]);
      await service.start(config);
      final response = await send('GET', '/missing');
      final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      expect(response.statusCode, 404);
      expect(body['routes'], contains('GET /health'));
    });

    test('OPTIONS 预检直接返回 204', () async {
      await service.start(MockServerConfig(port: 0, routes: [MockRoute(path: '/any')]));
      final response = await send('OPTIONS', '/any');
      expect(response.statusCode, 204);
      expect(response.headers.value('access-control-allow-methods'), contains('POST'));
    });

    test('运行中修改路由无需重启即可生效', () async {
      final config = MockServerConfig(port: 0, routes: [MockRoute(path: '/v1', body: 'one')]);
      await service.start(config);
      config.routes.add(MockRoute(path: '/v2', body: 'two'));
      service.update(config);
      final response = await send('GET', '/v2');
      expect(await utf8.decoder.bind(response).join(), 'two');
    });

    test('端口被占用时返回错误而不抛出', () async {
      final blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => blocker.close(force: true));
      final error = await service.start(MockServerConfig(port: blocker.port, routes: const []));
      expect(error, isNotNull);
      expect(service.running, isFalse);
    });
  });
}

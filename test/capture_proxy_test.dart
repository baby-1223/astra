import 'dart:convert';
import 'dart:io';

import 'package:astra/services/capture_proxy.dart';
import 'package:astra/services/mock_certs.dart';
import 'package:astra/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Storage storage;
  late CertificateAuthority ca;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('astra-capture-test');
    storage = Storage(root: tempDir);
    ca = await CertificateAuthority.loadOrCreate(storage);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('本地 CA', () {
    test('生成的证书可被自身信任，并可重复读取', () async {
      expect(ca.caPem, startsWith('-----BEGIN CERTIFICATE-----'));
      expect(ca.caPem, contains('-----END CERTIFICATE-----'));
      final restored = await CertificateAuthority.loadOrCreate(storage);
      expect(restored.caPem, ca.caPem);
    });

    test('导出 CA 证书到本地文件', () async {
      final path = await ca.exportCaCertificate();
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), contains('BEGIN CERTIFICATE'));
    });

    test('同一主机复用安全上下文', () {
      final first = ca.serverContextFor('example.com');
      final second = ca.serverContextFor('example.com');
      expect(identical(first, second), isTrue);
      expect(identical(ca.serverContextFor('other.example.com'), first), isFalse);
    });
  });

  group('CONNECT 目标解析', () {
    test('域名与端口', () {
      final target = parseConnectTarget('example.com:8443');
      expect(target?.host, 'example.com');
      expect(target?.port, 8443);
    });

    test('缺省端口为 443', () {
      expect(parseConnectTarget('example.com')?.port, 443);
    });

    test('IPv6 字面量', () {
      final target = parseConnectTarget('[::1]:9443');
      expect(target?.host, '::1');
      expect(target?.port, 9443);
    });

    test('非法输入返回 null', () {
      expect(parseConnectTarget(''), isNull);
      expect(parseConnectTarget('host:70000'), isNull);
      expect(parseConnectTarget('host:abc'), isNull);
    });
  });

  group('抓包记录转换', () {
    test('请求可直接回放为草稿', () {
      final record = CaptureRecord(
        id: '1',
        ts: 0,
        method: 'POST',
        url: 'https://api.example.com/orders?x=1',
        host: 'api.example.com',
        requestHeaders: {'content-type': 'application/json', 'x-token': 'abc'},
        requestBody: '{"sku":"A-1"}',
      );
      final request = requestFromCapture(record);
      expect(request.method, 'POST');
      expect(request.url, 'https://api.example.com/orders?x=1');
      expect(request.bodyMode, 'json');
      expect(request.body, '{"sku":"A-1"}');
      expect(request.headers.where((item) => item.k == 'x-token').single.v, 'abc');
    });

    test('响应可生成同路径的 Mock 路由', () {
      final record = CaptureRecord(
        id: '2',
        ts: 0,
        method: 'GET',
        url: 'https://api.example.com/users/42',
        host: 'api.example.com',
        status: 203,
        responseBody: '{"id":42}',
      );
      final route = mockRouteFromCapture(record);
      expect(route.method, 'GET');
      expect(route.path, '/users/42');
      expect(route.status, 203);
      expect(route.body, '{"id":42}');
    });
  });

  group('HTTP 抓包', () {
    late HttpServer upstream;
    late CaptureProxyService proxy;
    late HttpClient client;

    setUp(() async {
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        final trace = request.headers.value('x-token') ?? '';
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'path': request.uri.path,
          'query': request.uri.queryParameters,
          'trace': trace,
        }));
        await request.response.close();
      });
      proxy = CaptureProxyService();
      expect(await proxy.start(ca: ca, port: 0), isNull);
      client = HttpClient()
        ..findProxy = ((_) => 'PROXY 127.0.0.1:${proxy.port}')
        ..badCertificateCallback = ((_, _, _) => true);
    });

    tearDown(() async {
      client.close(force: true);
      await proxy.stop();
      await upstream.close(force: true);
    });

    test('转发请求并记录完整的请求与响应', () async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${upstream.port}/hello?x=1&y=2'),
      );
      request.headers.set('x-token', 'abc');
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;

      expect(response.statusCode, 200);
      expect(body['path'], '/hello');
      expect(body['trace'], 'abc');
      expect(body['query'], {'x': '1', 'y': '2'});

      final record = await _waitFor(proxy, (item) => item.url.contains('/hello'));
      expect(record.status, 200);
      expect(record.method, 'GET');
      expect(record.requestHeaders['x-token'], 'abc');
      expect(record.responseBody, contains('"trace":"abc"'));
      expect(record.error, isNull);
    });

    test('上游不可达时返回 502 并记录错误', () async {
      final deadPort = upstream.port;
      await upstream.close(force: true);
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$deadPort/gone'));
      final response = await request.close();
      expect(response.statusCode, 502);
      final record = await _waitFor(proxy, (item) => item.url.contains('/gone'));
      expect(record.error, isNotNull);
    });
  });

  group('HTTPS MITM', () {
    late HttpServer upstream;
    late CaptureProxyService proxy;
    late HttpClient client;

    setUp(() async {
      upstream = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        ca.serverContextFor('127.0.0.1'),
      );
      upstream.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'secure': true, 'path': request.uri.path}));
        await request.response.close();
      });
      proxy = CaptureProxyService();
      expect(await proxy.start(ca: ca, port: 0, mitmHttps: true), isNull);
      client = HttpClient(context: ca.trustedClientContext())
        ..findProxy = ((_) => 'PROXY 127.0.0.1:${proxy.port}');
    });

    tearDown(() async {
      client.close(force: true);
      await proxy.stop();
      await upstream.close(force: true);
    });

    test('解密 HTTPS 请求并记录响应体', () async {
      final request = await client.getUrl(
        Uri.parse('https://127.0.0.1:${upstream.port}/secure?token=1'),
      );
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;

      expect(response.statusCode, 200);
      expect(body['secure'], isTrue);

      final record = await _waitFor(proxy, (item) => item.url.contains('/secure'));
      expect(record.tunneled, isFalse);
      expect(record.status, 200);
      expect(record.url, contains('https://127.0.0.1'));
      expect(record.responseBody, contains('"secure":true'));
    });

    test('HTTPS 隧道模式只记录元数据', () async {
      await proxy.stop();
      proxy = CaptureProxyService();
      expect(await proxy.start(ca: ca, port: 0, mitmHttps: false), isNull);
      client.close(force: true);
      client = HttpClient(context: ca.trustedClientContext())
        ..findProxy = ((_) => 'PROXY 127.0.0.1:${proxy.port}');

      final request = await client.getUrl(Uri.parse('https://127.0.0.1:${upstream.port}/tunnel'));
      final response = await request.close();
      await utf8.decoder.bind(response).join();
      client.close(force: true);

      final record = await _waitFor(proxy, (item) => item.tunneled);
      expect(record.method, 'CONNECT');
      expect(record.url, contains('https://127.0.0.1'));
      expect(record.responseBody, isEmpty);
    });
  });
}

Future<CaptureRecord> _waitFor(
  CaptureProxyService proxy,
  bool Function(CaptureRecord record) test,
) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    for (final record in proxy.records) {
      if (test(record)) return record;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for capture record. Got: '
      '${proxy.records.map((item) => '${item.method} ${item.url}').toList()}');
}

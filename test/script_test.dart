import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:astra/models.dart';
import 'package:astra/services/script_service.dart';
import 'package:astra/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // flutter test 不会构建插件的原生产物，Windows 上缺少 quickjs_c_bridge.dll；
  // 正式构建的 exe 会由插件 CMake 安装该 DLL，因此仅在单元测试环境跳过。
  if (Platform.isWindows) {
    test('脚本引擎在 Windows 单元测试环境跳过', () {
      // 占位用例，保持测试文件非空
    }, skip: 'flutter test 未打包 flutter_js 的 quickjs_c_bridge.dll');
    return;
  }

  final service = ScriptService();

  ScriptInput buildInput({
    String method = 'GET',
    String url = 'https://api.example.com/users',
    String bodyMode = 'none',
    String body = '',
    Map<String, String>? headers,
    Map<String, String>? env,
    String event = 'prerequest',
  }) {
    return ScriptInput(
      method: method,
      url: url,
      bodyMode: bodyMode,
      body: body,
      headers: headers ?? {'Accept': 'application/json'},
      env: env ?? {'baseUrl': 'https://api.example.com', 'token': 'old-token'},
      vars: const {},
      requestName: 'users',
      event: event,
    );
  }

  HttpResult buildResponse() {
    const text = '{"name":"Astra","items":[1,2,3]}';
    return HttpResult(
      status: 200,
      reason: 'OK',
      headers: {
        'content-type': ['application/json'],
        'x-trace': ['abc'],
      },
      bytes: Uint8List.fromList(utf8.encode(text)),
      text: text,
      ms: 12,
      size: text.length,
    );
  }

  group('前置脚本', () {
    test('可改写请求方法、地址、Header 与变量', () {
      final outcome = service.run(
        source: '''
          pm.environment.set("token", "new-token");
          pm.variables.set("suffix", "42");
          pm.request.method = "post";
          pm.request.url = "https://api.example.com/items/{{suffix}}";
          pm.request.headers.add({ key: "X-Debug", value: "1" });
          pm.request.headers.upsert({ key: "accept", value: "text/plain" });
          console.log("hello", 1 + 1);
        ''',
        input: buildInput(),
      )!;

      expect(outcome.error, isNull);
      expect(outcome.method, 'POST');
      // 与 Postman 一致：脚本中的 URL 保留 {{变量}} 原样，发送前再统一替换
      expect(outcome.url, 'https://api.example.com/items/{{suffix}}');
      expect(outcome.env['token'], 'new-token');
      expect(outcome.vars['suffix'], '42');

      final headers = {
        for (final header in outcome.headers) header.key.toLowerCase(): header.value,
      };
      expect(headers['x-debug'], '1');
      expect(headers['accept'], 'text/plain');
      expect(outcome.logs.map((log) => log.message).join(' '), contains('hello 2'));
    });

    test('可读取环境变量并替换变量占位符', () {
      final outcome = service.run(
        source: '''
          console.log(pm.environment.get("baseUrl"));
          console.log(pm.variables.replaceIn("{{baseUrl}}/v1/{{token}}"));
          pm.request.body.mode = "raw";
          pm.request.body.raw = JSON.stringify({ ok: true });
        ''',
        input: buildInput(bodyMode: 'json', body: '{}'),
      )!;

      expect(outcome.error, isNull);
      final messages = outcome.logs.map((log) => log.message).join('\n');
      expect(messages, contains('https://api.example.com'));
      expect(messages, contains('https://api.example.com/v1/old-token'));
      expect(outcome.bodyMode, 'raw');
      expect(outcome.body, '{"ok":true}');
    });
  });

  group('后置脚本', () {
    test('可断言响应并写入控制台与变量', () {
      final outcome = service.run(
        source: '''
          console.log("name", pm.response.json().name);
          pm.test("状态码为 200", function () {
            pm.response.to.have.status(200);
          });
          pm.test("返回 Astra", function () {
            pm.expect(pm.response.json().name).to.eql("Astra");
          });
          pm.test("状态码为 404", function () {
            pm.expect(pm.response.code).to.equal(404);
          });
          pm.test("响应时间小于 1 秒", function () {
            pm.expect(pm.response.responseTime).to.be.below(1000);
          });
          pm.environment.set("lastCode", pm.response.code);
        ''',
        input: buildInput(event: 'test'),
        response: buildResponse(),
      )!;

      expect(outcome.error, isNull);
      expect(outcome.tests.length, 4);
      expect(outcome.tests.where((test) => test.passed).length, 3);
      final failed = outcome.tests.firstWhere((test) => !test.passed);
      expect(failed.name, '状态码为 404');
      expect(failed.error, isNotNull);
      expect(outcome.env['lastCode'], '200');
      expect(outcome.logs.map((log) => log.message).join(' '), contains('name Astra'));
    });

    test('可通过 pm.response 读取 Header 与文本', () {
      final outcome = service.run(
        source: '''
          pm.test("header", function () {
            pm.expect(pm.response.headers.get("X-Trace")).to.equal("abc");
          });
          pm.test("text", function () {
            pm.expect(pm.response.text()).to.include("Astra");
          });
        ''',
        input: buildInput(event: 'test'),
        response: buildResponse(),
      )!;

      expect(outcome.tests.every((test) => test.passed), isTrue);
    });
  });

  group('异常处理', () {
    test('运行时错误会被记录', () {
      final outcome = service.run(
        source: 'throw new Error("boom");',
        input: buildInput(),
      )!;
      expect(outcome.error, contains('boom'));
    });

    test('语法错误会被记录', () {
      final outcome = service.run(
        source: 'pm.environment.set("a", "1"',
        input: buildInput(),
      )!;
      expect(outcome.error, isNotNull);
    });

    test('空脚本不执行', () {
      expect(service.run(source: '  ', input: buildInput()), isNull);
    });
  });

  group('AppState 发送流程', () {
    test('前置脚本改写请求、后置脚本断言响应', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'trace': request.headers.value('x-astra'),
          'method': request.method,
          'body': body,
        }));
        await request.response.close();
      });

      final state = AppState();
      state.request.url = 'http://127.0.0.1:${server.port}/echo';
      state.request.preScript = '''
        pm.request.headers.add({ key: "X-Astra", value: "prerequest-ok" });
        pm.environment.set("flag", "1");
        console.log("pre done");
      ''';
      state.request.postScript = '''
        pm.test("前置脚本注入的 Header 生效", function () {
          pm.expect(pm.response.json().trace).to.equal("prerequest-ok");
        });
        console.log("post done");
      ''';

      await state.send();

      expect(state.response?.status, 200);
      expect(state.scriptRan, isTrue);
      expect(state.scriptError, isNull);
      expect(state.scriptTests.length, 1);
      expect(state.scriptTests.single.passed, isTrue);
      expect(
        state.scriptLogs.map((log) => log.message).toList(),
        ['pre done', 'post done'],
      );
      expect(
        state.env.vars.any((item) => item.k == 'flag' && item.v == '1'),
        isTrue,
      );

      await server.close(force: true);
    });

    test('脚本失败不影响请求发送', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.write('ok');
        await request.response.close();
      });

      final state = AppState();
      state.request.url = 'http://127.0.0.1:${server.port}/';
      state.request.preScript = 'throw new Error("pre boom");';

      await state.send();

      expect(state.response?.status, 200);
      expect(state.scriptError, contains('pre boom'));

      await server.close(force: true);
    });
  });

  group('JSONPath', () {
    test('支持通配符、递归与负索引', () {
      const text = '{"data":{"items":[{"id":1},{"id":2}],"token":"t-1"},"meta":{"token":"t-2"}}';
      final response = HttpResult(
        status: 200,
        reason: 'OK',
        headers: {
          'content-type': ['application/json'],
        },
        bytes: Uint8List.fromList(utf8.encode(text)),
        text: text,
        ms: 5,
        size: text.length,
      );

      final outcome = service.run(
        source: '''
          const ids = pm.jsonPath('\$.data.items[*].id');
          pm.environment.set('ids', ids.join(','));
          pm.environment.set('last', String(pm.jsonPath('\$.data.items[-1].id')));
          pm.environment.set('recursive', pm.jsonPath('\$..token').join('|'));
          pm.test('wildcard returns array', () => pm.expect(Array.isArray(ids)).to.equal(true));
          pm.test('recursive finds both tokens', () => pm.expect(pm.jsonPath('\$..token').length).to.equal(2));
        ''',
        input: buildInput(event: 'test'),
        response: response,
      )!;

      expect(outcome.error, isNull);
      expect(outcome.env['ids'], '1,2');
      expect(outcome.env['last'], '2');
      expect(outcome.env['recursive'], 't-1|t-2');
      expect(outcome.tests.length, 2);
      expect(outcome.tests.every((test) => test.passed), isTrue);
    });
  });

  group('集合与文件夹脚本', () {
    test('运行器按 集合 → 文件夹 → 请求 顺序合并执行', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response.write('ok');
        await request.response.close();
      });

      final state = AppState();
      state.env.vars = [KV(k: 'order', v: '')];
      final group = state.createGroup('Scripts', 'http');
      group.preScript =
          "pm.environment.set('order', (pm.environment.get('order') || '') + 'C');";
      final folder = state.createFolder(group.id, '', 'Inner');
      folder.preScript =
          "pm.environment.set('order', (pm.environment.get('order') || '') + 'F');";
      final entry = CollectionEntry(
        name: 'ping',
        groupId: group.id,
        folderId: folder.id,
        mode: 'http',
        request: ApiRequest(
          method: 'GET',
          url: 'http://127.0.0.1:${server.port}/',
          preScript:
              "pm.environment.set('order', (pm.environment.get('order') || '') + 'R');",
        ),
      );
      state.collections.add(entry);

      final report = await state.runCollection(groupId: group.id);

      expect(report.failed, 0);
      final order = state.env.vars.firstWhere((item) => item.k == 'order').v;
      expect(order, 'CFR');

      await server.close(force: true);
    });
  });
}

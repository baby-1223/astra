import 'dart:convert';
import 'dart:io';

import 'package:astra/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面运行时脚本引擎可用', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'trace': request.headers.value('x-astra'),
        'token': request.headers.value('authorization'),
      }));
      await request.response.close();
    });

    final state = AppState();
    state.request.url = 'http://127.0.0.1:${server.port}/echo';
    state.request.preScript = '''
      pm.request.headers.add({ key: "X-Astra", value: "desktop-ok" });
      pm.environment.set("token", "desktop-token");
    ''';
    state.request.postScript = '''
      pm.test("Header 注入成功", function () {
        pm.expect(pm.response.json().trace).to.equal("desktop-ok");
      });
      console.log("script running");
    ''';

    await tester.runAsync(() => state.send());

    expect(state.response?.status, 200);
    expect(state.scriptError, isNull);
    expect(state.scriptTests.length, 1);
    expect(state.scriptTests.single.passed, isTrue);
    expect(state.scriptLogs.single.message, 'script running');
    expect(
      state.env.vars.any((item) => item.k == 'token' && item.v == 'desktop-token'),
      isTrue,
    );

    state.dispose();
    await server.close(force: true);
  });
}

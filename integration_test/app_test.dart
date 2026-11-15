import 'package:astra/main.dart' as app;
import 'package:astra/ui/bound_text_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('发送 HTTP 请求并展示响应', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));

    final urlField = find.byType(BoundTextField).first;
    await tester.enterText(urlField, 'http://127.0.0.1:18123/api/users');
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('发送').first);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.textContaining('200 OK').evaluate().isNotEmpty) break;
    }

    expect(find.textContaining('200 OK'), findsOneWidget);
    expect(find.textContaining('Nova'), findsOneWidget);
  });
}

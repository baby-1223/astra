import 'package:astra/models.dart';
import 'package:astra/services/codegen.dart';
import 'package:astra/services/env_vars.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseVariableText', () {
    test('parses .env with export, quotes and comments', () {
      final rows = parseVariableText(
        '# comment\nBASE_URL=https://api.example.com\nexport TOKEN="abc 123"\nSINGLE=\'a=b\'\n',
      );
      expect(rows.map((row) => '${row.k}=${row.v}').toList(), [
        'BASE_URL=https://api.example.com',
        'TOKEN=abc 123',
        'SINGLE=a=b',
      ]);
    });

    test('parses CSV with header and quoted fields', () {
      final rows = parseVariableText('key,value\nBASE_URL,https://x.test\nNOTE,"hello, world"\n');
      expect(rows.map((row) => '${row.k}=${row.v}').toList(), [
        'BASE_URL=https://x.test',
        'NOTE=hello, world',
      ]);
    });

    test('CSV without header keeps the first row', () {
      final rows = parseVariableText('A,1\nB,2');
      expect(rows.length, 2);
      expect(rows.first.k, 'A');
    });

    test('returns empty for comments only', () {
      expect(parseVariableText('\n# only\n'), isEmpty);
    });
  });

  group('toDotEnv', () {
    test('quotes values that need escaping', () {
      final text = toDotEnv([
        KV(k: 'A', v: '1'),
        KV(k: 'B', v: 'hello world'),
        KV(k: 'C', v: ''),
      ]);
      expect(text, 'A=1\nB="hello world"\nC=\n');
    });
  });

  group('generateCode', () {
    final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer t'};

    test('python uses requests', () {
      final code = generateCode('POST', 'https://x.test', headers, '{"a":1}', CodeLanguage.python);
      expect(code, contains('import requests'));
      expect(code, contains('requests.request("POST", url, headers=headers'));
    });

    test('javascript uses fetch in async iife', () {
      final code = generateCode('POST', 'https://x.test', headers, '{"a":1}', CodeLanguage.javascript);
      expect(code, contains('(async () => {'));
      expect(code, contains('await fetch(url'));
    });

    test('go uses net/http', () {
      final code = generateCode('GET', 'https://x.test', headers, '', CodeLanguage.go);
      expect(code, contains('http.NewRequest("GET", "https://x.test", nil)'));
    });

    test('java uses HttpClient', () {
      final code = generateCode('POST', 'https://x.test', headers, 'body', CodeLanguage.java);
      expect(code, contains('HttpRequest.newBuilder()'));
      expect(code, contains('BodyPublishers.ofString'));
    });

    test('http client renders plain text request', () {
      final code = generateCode('GET', 'https://x.test', headers, '', CodeLanguage.httpClient);
      expect(code, startsWith('GET https://x.test\n'));
      expect(code, endsWith('\n'));
    });
  });
}

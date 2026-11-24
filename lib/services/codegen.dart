/// 把请求渲染成其他语言的代码片段，便于粘贴到项目里直接调试。
library;

enum CodeLanguage { python, javascript, go, java, httpClient }

String codeLanguageLabel(CodeLanguage language) {
  switch (language) {
    case CodeLanguage.python:
      return 'Python (requests)';
    case CodeLanguage.javascript:
      return 'JavaScript (fetch)';
    case CodeLanguage.go:
      return 'Go (net/http)';
    case CodeLanguage.java:
      return 'Java (HttpClient)';
    case CodeLanguage.httpClient:
      return 'IntelliJ HTTP Client';
  }
}

/// [url]、[headers]、[body] 应是已完成变量替换的最终值。
String generateCode(
  String method,
  String url,
  Map<String, String> headers,
  String body,
  CodeLanguage language,
) {
  final verb = method.toUpperCase();
  final hasBody = body.isNotEmpty && verb != 'GET' && verb != 'HEAD';
  switch (language) {
    case CodeLanguage.python:
      return _python(verb, url, headers, hasBody ? body : null);
    case CodeLanguage.javascript:
      return _javascript(verb, url, headers, hasBody ? body : null);
    case CodeLanguage.go:
      return _go(verb, url, headers, hasBody ? body : null);
    case CodeLanguage.java:
      return _java(verb, url, headers, hasBody ? body : null);
    case CodeLanguage.httpClient:
      return _httpClient(verb, url, headers, hasBody ? body : null);
  }
}

String _python(String method, String url, Map<String, String> headers, String? body) {
  final out = StringBuffer('import requests\n\n');
  out.writeln('url = "${_escape(url, '"')}"');
  out.writeln('headers = {');
  headers.forEach((key, value) {
    out.writeln('    "${_escape(key, '"')}": "${_escape(value, '"')}",');
  });
  out.writeln('}');
  if (body != null) out.writeln('payload = "${_escape(body, '"')}"');
  out.writeln();
  final data = body == null ? '' : ', data=payload.encode("utf-8")';
  out.writeln(
      'response = requests.request("${_escape(method, '"')}", url, headers=headers$data, timeout=30)');
  out.writeln('print(response.status_code)');
  out.writeln('print(response.text)');
  return out.toString();
}

String _javascript(String method, String url, Map<String, String> headers, String? body) {
  final out = StringBuffer();
  out.writeln('const url = "${_escape(url, '"')}";');
  out.writeln('const headers = {');
  headers.forEach((key, value) {
    out.writeln('  "${_escape(key, '"')}": "${_escape(value, '"')}",');
  });
  out.writeln('};');
  if (body != null) out.writeln('const body = "${_escape(body, '"')}";');
  out.writeln();
  out.writeln('(async () => {');
  out.writeln('  const response = await fetch(url, {');
  out.writeln('    method: "${_escape(method, '"')}",');
  out.writeln('    headers,');
  if (body != null) out.writeln('    body,');
  out.writeln('  });');
  out.writeln('  console.log(response.status, await response.text());');
  out.writeln('})();');
  return out.toString();
}

String _go(String method, String url, Map<String, String> headers, String? body) {
  final out = StringBuffer('package main\n\nimport (\n\t"fmt"\n\t"io"\n\t"net/http"\n');
  if (body != null) out.writeln('\t"strings"');
  out.writeln(')\n\nfunc main() {');
  if (body != null) {
    out.writeln('\tbody := strings.NewReader("${_escape(body, '"')}")');
  }
  out.writeln(
      '\treq, err := http.NewRequest("${_escape(method, '"')}", "${_escape(url, '"')}", ${body != null ? 'body' : 'nil'})');
  out.writeln('\tif err != nil {\n\t\tpanic(err)\n\t}');
  headers.forEach((key, value) {
    out.writeln('\treq.Header.Set("${_escape(key, '"')}", "${_escape(value, '"')}")');
  });
  out.writeln('\tresp, err := (&http.Client{}).Do(req)');
  out.writeln('\tif err != nil {\n\t\tpanic(err)\n\t}');
  out.writeln('\tdefer resp.Body.Close()');
  out.writeln('\tdata, err := io.ReadAll(resp.Body)');
  out.writeln('\tif err != nil {\n\t\tpanic(err)\n\t}');
  out.writeln('\tfmt.Println(resp.Status)');
  out.writeln('\tfmt.Println(string(data))');
  out.writeln('}');
  return out.toString();
}

String _java(String method, String url, Map<String, String> headers, String? body) {
  final out = StringBuffer();
  out.writeln('import java.net.URI;');
  out.writeln('import java.net.http.HttpClient;');
  out.writeln('import java.net.http.HttpRequest;');
  out.writeln('import java.net.http.HttpResponse;\n');
  out.writeln('public class AstraRequest {');
  out.writeln('    public static void main(String[] args) throws Exception {');
  out.writeln('        HttpClient client = HttpClient.newHttpClient();');
  out.writeln('        HttpRequest request = HttpRequest.newBuilder()');
  out.writeln('                .uri(URI.create("${_escape(url, '"')}"))');
  headers.forEach((key, value) {
    out.writeln('                .header("${_escape(key, '"')}", "${_escape(value, '"')}")');
  });
  final publisher = body == null
      ? 'HttpRequest.BodyPublishers.noBody()'
      : 'HttpRequest.BodyPublishers.ofString("${_escape(body, '"')}")';
  out.writeln('                .method("${_escape(method, '"')}", $publisher)');
  out.writeln('                .build();');
  out.writeln(
      '        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());');
  out.writeln('        System.out.println(response.statusCode());');
  out.writeln('        System.out.println(response.body());');
  out.writeln('    }\n}');
  return out.toString();
}

String _httpClient(String method, String url, Map<String, String> headers, String? body) {
  final out = StringBuffer('$method $url\n');
  headers.forEach((key, value) {
    out.writeln('$key: $value');
  });
  if (body != null) out.writeln('\n$body');
  return out.toString();
}

String _escape(String value, String quote) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (char == r'\') {
      out.write(r'\\');
    } else if (char == '\n') {
      out.write(r'\n');
    } else if (char == '\r') {
      out.write(r'\r');
    } else if (char == '\t') {
      out.write(r'\t');
    } else if (char == quote) {
      out.write('\\$quote');
    } else {
      out.write(char);
    }
  }
  return out.toString();
}

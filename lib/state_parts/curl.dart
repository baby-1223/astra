part of '../state.dart';

/// cURL 导入与导出。
mixin _CurlTools {
  Map<String, String> collectHeaders([ApiRequest? req]);
  String buildUrl([ApiRequest? req]);
  String buildBody([ApiRequest? req]);

  String curlFor(ApiRequest req) {
    final headers = collectHeaders(req);
    final body = buildBody(req);
    String url;
    try {
      url = buildUrl(req);
    } catch (_) {
      url = req.url;
    }
    final buffer = StringBuffer('curl -X ${req.method.toUpperCase()} ');
    buffer.write(_shellQuote(url));
    headers.forEach((key, value) {
      buffer.write(' \\\n  -H ${_shellQuote('$key: $value')}');
    });
    if (body.isNotEmpty &&
        req.method.toUpperCase() != 'GET' &&
        req.method.toUpperCase() != 'HEAD') {
      buffer.write(' \\\n  --data-raw ${_shellQuote(body)}');
    }
    if (!req.options.followRedirects) buffer.write(' \\\n  --no-location');
    if (!req.options.rejectUnauthorized) buffer.write(' \\\n  -k');
    return buffer.toString();
  }

  String _shellQuote(String value) {
    if (!value.contains(RegExp(r'''[\s'"$`\\!*?&|<>()\[\]{};#]'''))) return value;
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  /// 解析 cURL 命令，返回新建的请求；解析失败抛出 FormatException。
  ApiRequest parseCurl(String input) {
    var text = input.trim();
    if (text.isEmpty) throw const FormatException('Enter a cURL command');
    // 去掉复制时常见的行首提示符与换行续行
    text = text.replaceAll(RegExp(r'\\\r?\n'), ' ').replaceAll(RegExp(r'\r?\n'), ' ');
    final tokens = _tokenizeShell(text);
    if (tokens.isEmpty || !tokens.first.toLowerCase().contains('curl')) {
      throw const FormatException('Content is not a valid cURL command');
    }
    final req = ApiRequest();
    final headers = <KV>[];
    final forms = <FormRow>[];
    String? url;
    String? data;
    String? method;
    var followRedirects = true;
    var verify = true;
    var bodyMode = 'none';

    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      String next() => i + 1 < tokens.length ? tokens[++i] : '';
      switch (token) {
        case '-X':
        case '--request':
          method = next().toUpperCase();
        case '-H':
        case '--header':
          final raw = next();
          final index = raw.indexOf(':');
          if (index > 0) {
            headers.add(KV(on: true, k: raw.substring(0, index).trim(), v: raw.substring(index + 1).trim()));
          }
        case '-d':
        case '--data':
        case '--data-raw':
        case '--data-binary':
        case '--data-ascii':
          data = next();
          method ??= 'POST';
        case '-F':
        case '--form':
          final raw = next();
          final index = raw.indexOf('=');
          if (index > 0) {
            final key = raw.substring(0, index);
            final value = raw.substring(index + 1);
            if (value.startsWith('@')) {
              forms.add(FormRow(
                on: true,
                k: key,
                type: 'file',
                file: UploadFile(
                  name: value.substring(1).split('/').last,
                  path: value.substring(1),
                  mime: mimeFor(value.substring(1)),
                  size: 0,
                  stale: true,
                ),
              ));
            } else {
              forms.add(FormRow(on: true, k: key, v: value));
            }
          }
          bodyMode = 'form-data';
          method ??= 'POST';
        case '-u':
        case '--user':
          final raw = next();
          final index = raw.indexOf(':');
          req.auth
            ..type = 'basic'
            ..username = index >= 0 ? raw.substring(0, index) : raw
            ..password = index >= 0 ? raw.substring(index + 1) : '';
        case '-L':
        case '--location':
          followRedirects = true;
        case '-k':
        case '--insecure':
          verify = false;
        case '--url':
          url = next();
        case '-b':
        case '--cookie':
          final raw = next();
          headers.add(KV(on: true, k: 'Cookie', v: raw));
        default:
          if (!token.startsWith('-') && url == null) url = token;
      }
    }

    if (url == null || url.trim().isEmpty) throw const FormatException('No request URL found');
    req.url = url;
    req.method = method ?? (data != null ? 'POST' : 'GET');
    if (headers.isEmpty) headers.add(KV());
    req.headers = headers;
    req.options
      ..followRedirects = followRedirects
      ..rejectUnauthorized = verify;
    if (forms.isNotEmpty) {
      req.bodyMode = 'form-data';
      req.formData = forms;
    } else if (data != null) {
      final trimmed = data.trimLeft();
      final looksJson = trimmed.startsWith('{') || trimmed.startsWith('[');
      req.bodyMode = looksJson ? 'json' : 'text';
      req.body = data;
    } else if (bodyMode != 'none') {
      req.bodyMode = bodyMode;
    }
    return req;
  }

  List<String> _tokenizeShell(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    var hasContent = false;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (quote != null) {
        if (ch == '\\' && quote == '"' && i + 1 < input.length) {
          buffer.write(input[++i]);
        } else if (ch == quote) {
          quote = null;
        } else {
          buffer.write(ch);
        }
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        hasContent = true;
        continue;
      }
      if (ch == '\\' && i + 1 < input.length) {
        buffer.write(input[++i]);
        hasContent = true;
        continue;
      }
      if (ch.trim().isEmpty) {
        if (hasContent) {
          tokens.add(buffer.toString());
          buffer.clear();
          hasContent = false;
        }
        continue;
      }
      buffer.write(ch);
      hasContent = true;
    }
    if (hasContent) tokens.add(buffer.toString());
    return tokens;
  }
}

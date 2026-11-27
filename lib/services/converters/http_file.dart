part of '../converters.dart';

const _httpMethods = {
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
  'TRACE',
};

enum _HttpState { outside, headers, body }

/// Parses IntelliJ HTTP Client `.http` / `.rest` files into one Astra collection.
ImportResult importHttpFile(String text, String fileName) {
  final baseName = fileName.contains('.')
      ? fileName.substring(0, fileName.lastIndexOf('.'))
      : fileName;
  final group = CollectionGroup(
    name: baseName.trim().isEmpty ? 'HTTP File' : baseName.trim(),
  );
  final entries = <CollectionEntry>[];
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

  ApiRequest? current;
  var pendingName = '';
  var state = _HttpState.outside;
  var headers = <KV>[];
  final body = StringBuffer();

  void flush() {
    final request = current;
    if (request == null) return;
    request.headers = headers.isEmpty ? [KV()] : headers;
    _applyHttpBody(request, body.toString().trimRight());
    var name = pendingName;
    if (name.isEmpty) name = _fallbackHttpName(request);
    entries.add(CollectionEntry(
      groupId: group.id,
      name: name,
      request: request,
    ));
    current = null;
    headers = <KV>[];
    body.clear();
    pendingName = '';
  }

  var index = 0;
  while (index < lines.length) {
    final raw = lines[index];
    final line = raw.trim();
    switch (state) {
      case _HttpState.outside:
        if (line.isEmpty) {
          // skip
        } else if (line.startsWith('###')) {
          pendingName = line.substring(3).trim();
        } else if (_isHttpNameHint(line)) {
          pendingName = line.substring(line.indexOf('@name') + 5).trim();
        } else if (_isHttpComment(line)) {
          // skip
        } else if (_isHttpVariable(line)) {
          final separator = line.indexOf('=');
          final key = line.substring(1, separator).trim();
          if (key.isNotEmpty) {
            group.variables.add(KV(
              k: key,
              v: line.substring(separator + 1).trim().replaceAll('"', ''),
            ));
          }
        } else if (line.startsWith('>')) {
          index = _skipHttpHandler(lines, index);
          continue;
        } else {
          final parsed = _parseHttpRequestLine(line);
          if (parsed != null) {
            current = ApiRequest(method: parsed.$1, url: parsed.$2);
            state = _HttpState.headers;
          }
        }
      case _HttpState.headers:
        if (line.startsWith('###')) {
          flush();
          pendingName = line.substring(3).trim();
          state = _HttpState.outside;
        } else if (line.isEmpty) {
          state = _HttpState.body;
        } else if (_isHttpNameHint(line)) {
          pendingName = line.substring(line.indexOf('@name') + 5).trim();
        } else if (_isHttpComment(line)) {
          // skip
        } else if (line.startsWith('>')) {
          flush();
          state = _HttpState.outside;
          index = _skipHttpHandler(lines, index);
          continue;
        } else {
          final header = _parseHttpHeader(line);
          if (header != null) {
            headers.add(KV(k: header.$1, v: header.$2));
          } else {
            body.writeln(raw);
            state = _HttpState.body;
          }
        }
      case _HttpState.body:
        if (line.startsWith('###')) {
          flush();
          pendingName = line.substring(3).trim();
          state = _HttpState.outside;
        } else if (line.startsWith('>')) {
          flush();
          state = _HttpState.outside;
          index = _skipHttpHandler(lines, index);
          continue;
        } else {
          body.writeln(raw);
        }
    }
    index++;
  }
  flush();

  if (group.variables.isEmpty) group.variables.add(KV());
  return ImportResult(
    collections: entries,
    variables: const [],
    name: group.name,
    groups: [group],
  );
}

bool _isHttpComment(String line) =>
    line.startsWith('#') || line.startsWith('//');

bool _isHttpNameHint(String line) =>
    line.startsWith('# @name') || line.startsWith('// @name');

bool _isHttpVariable(String line) {
  if (!line.startsWith('@')) return false;
  return line.indexOf('=') > 1;
}

(String, String)? _parseHttpRequestLine(String line) {
  if (line.startsWith('{') || line.startsWith('@')) return null;
  final match = RegExp(r'^([A-Za-z]+)\s+(.+)$').firstMatch(line);
  if (match != null) {
    final method = match.group(1)!.toUpperCase();
    if (_httpMethods.contains(method)) {
      return (method, match.group(2)!.trim());
    }
  }
  if (line.startsWith('http://') ||
      line.startsWith('https://') ||
      line.startsWith('{{')) {
    return ('GET', line);
  }
  return null;
}

(String, String)? _parseHttpHeader(String line) {
  if (line.startsWith('{') || line.startsWith('[') || line.startsWith('//')) {
    return null;
  }
  final separator = line.indexOf(':');
  if (separator <= 0) return null;
  final key = line.substring(0, separator).trim();
  if (key.isEmpty || key.contains(RegExp(r'\s'))) return null;
  return (key, line.substring(separator + 1).trim());
}

int _skipHttpHandler(List<String> lines, int start) {
  var index = start;
  if (lines[index].trim().startsWith('> {%')) {
    while (index < lines.length && !lines[index].contains('%}')) {
      index++;
    }
  }
  return index + 1;
}

void _applyHttpBody(ApiRequest request, String rawBody) {
  if (rawBody.trim().isEmpty) {
    request.bodyMode = 'none';
    return;
  }
  final contentType = request.headers
      .where((kv) => kv.k.toLowerCase() == 'content-type')
      .map((kv) => kv.v.toLowerCase())
      .firstOrNull ??
      '';
  request.body = rawBody;
  if (contentType.contains('json')) {
    request.bodyMode = 'json';
  } else if (contentType.contains('x-www-form-urlencoded')) {
    request.bodyMode = 'form';
    request.form = rawBody
        .split('&')
        .where((pair) => pair.isNotEmpty)
        .map((pair) {
          final separator = pair.indexOf('=');
          if (separator < 0) {
            return KV(k: _decodeHttpValue(pair), v: '');
          }
          return KV(
            k: _decodeHttpValue(pair.substring(0, separator)),
            v: _decodeHttpValue(pair.substring(separator + 1)),
          );
        })
        .toList();
    if (request.form.isEmpty) request.form.add(KV());
  } else if (rawBody.trimLeft().startsWith('{') ||
      rawBody.trimLeft().startsWith('[')) {
    request.bodyMode = 'json';
  } else {
    request.bodyMode = 'text';
  }
}

String _decodeHttpValue(String value) {
  try {
    return Uri.decodeQueryComponent(value);
  } catch (_) {
    return value;
  }
}

String _fallbackHttpName(ApiRequest request) {
  final withoutScheme = request.url.contains('://')
      ? request.url.substring(request.url.indexOf('://') + 3)
      : request.url;
  final path = withoutScheme.contains('/')
      ? withoutScheme.substring(withoutScheme.indexOf('/') + 1)
      : '';
  final cleanPath = path.split('?').first;
  final label = cleanPath.replaceAll(RegExp(r'^/+|/+$'), '');
  return label.isEmpty ? request.method : '${request.method} /$label';
}

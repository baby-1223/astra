import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models.dart';

/// 一条 Mock 路由的匹配结果。
class MockRouteMatch {
  final MockRoute route;
  final Map<String, String> pathParams;

  MockRouteMatch(this.route, this.pathParams);
}

/// 一条 Mock Server 命中记录，仅保存在内存中。
class MockHit {
  final int ts;
  final String method;
  final String path;
  final int status;
  final String routeName;
  final int ms;
  final bool matched;

  MockHit({
    required this.ts,
    required this.method,
    required this.path,
    required this.status,
    required this.routeName,
    required this.ms,
    required this.matched,
  });
}

/// 模板渲染时可用的上下文。
class MockTemplateContext {
  final Map<String, String> pathParams;
  final Map<String, String> query;
  final Map<String, String> headers;
  final String body;

  MockTemplateContext({
    this.pathParams = const {},
    this.query = const {},
    this.headers = const {},
    this.body = '',
  });
}

/// 把完整 URL 转成 Mock 路由使用的路径模式，例如
/// `https://api.example.com/users/42?x=1` → `/users/:id`。
String mockPathFromUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return '/';
  if (!uri.hasScheme && !trimmed.startsWith('/')) return '/';
  if (uri.path.isEmpty) return '/';
  final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
  if (segments.isEmpty) return '/';
  return '/${segments.map((segment) => RegExp(r'^\d+$').hasMatch(segment) ? ':id' : segment).join('/')}';
}

List<String> _segments(String path) {
  final normalized = path.startsWith('/') ? path : '/$path';
  return normalized.split('/').where((item) => item.isNotEmpty).toList();
}

/// 在路由列表中查找最佳匹配；静态片段优先于参数，参数优先于通配符。
MockRouteMatch? matchMockRoute(
  List<MockRoute> routes,
  String method,
  String path,
) {
  final target = _segments(path);
  MockRouteMatch? best;
  var bestScore = -1;
  for (final route in routes) {
    if (!route.enabled) continue;
    final routeMethod = route.method.trim().toUpperCase();
    if (routeMethod.isNotEmpty && routeMethod != 'ANY' && routeMethod != method.toUpperCase()) {
      continue;
    }
    final pattern = _segments(route.path);
    final params = <String, String>{};
    var score = 0;
    var matched = true;
    for (var i = 0; i < pattern.length; i++) {
      final part = pattern[i];
      if (part == '*') {
        params['rest'] = target.skip(i).map(Uri.decodeComponent).join('/');
        score += 1;
        matched = i <= target.length;
        break;
      }
      if (i >= target.length) {
        matched = false;
        break;
      }
      if (part.startsWith(':') && part.length > 1) {
        params[part.substring(1)] = Uri.decodeComponent(target[i]);
        score += 2;
        continue;
      }
      if (part != target[i]) {
        matched = false;
        break;
      }
      score += 3;
    }
    if (matched && pattern.length != target.length && !pattern.contains('*')) {
      matched = false;
    }
    if (!matched) continue;
    if (score > bestScore) {
      bestScore = score;
      best = MockRouteMatch(route, params);
    }
  }
  return best;
}

/* ------------------------------------------------------------------ */
/* 随机数据                                                            */
/* ------------------------------------------------------------------ */

const List<String> _firstNames = [
  'Ava', 'Liam', 'Mia', 'Noah', 'Zoe', 'Ethan', 'Ivy', 'Leo',
  'Nora', 'Kai', 'Ruby', 'Owen', 'Luna', 'Finn', 'Aria', 'Milo',
];
const List<String> _lastNames = [
  'Chen', 'Miller', 'Garcia', 'Kim', 'Singh', 'Novak', 'Silva', 'Brown',
  'Wang', 'Lee', 'Patel', 'Rossi', 'Dubois', 'Schmidt', 'Tanaka', 'Olsen',
];
const List<String> _cities = [
  'Shanghai', 'Singapore', 'Tokyo', 'Berlin', 'Toronto', 'Sydney',
  'Amsterdam', 'Seattle', 'Barcelona', 'Seoul',
];
const List<String> _countries = [
  'China', 'Singapore', 'Japan', 'Germany', 'Canada', 'Australia',
  'Netherlands', 'United States', 'Spain', 'South Korea',
];
const List<String> _companies = [
  'Northwind Labs', 'Blue Harbor', 'Aster Works', 'Pine & Co',
  'Lumen Studio', 'Riverstone', 'Cobalt Group', 'Nimbus Tech',
];
const List<String> _words = [
  'orbit', 'harbor', 'canvas', 'signal', 'meadow', 'cobalt', 'thunder',
  'velvet', 'quartz', 'ember', 'lumen', 'operator',
];
const List<String> _colors = [
  '#38BDF8', '#8B5CF6', '#34D399', '#FBBF24', '#FB7185', '#A3E635',
];

String _uuid(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((item) => item.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _pick(List<String> source, Random random) => source[random.nextInt(source.length)];

String _randomToken(String token, Random random) {
  switch (token) {
    case 'guid':
    case 'randomUUID':
    case 'uuid':
      return _uuid(random);
    case 'timestamp':
      return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    case 'isoTimestamp':
      return DateTime.now().toUtc().toIso8601String();
    case 'randomDate':
      final start = DateTime(2020, 1, 1);
      final days = DateTime.now().difference(start).inDays;
      return start.add(Duration(days: random.nextInt(days + 1))).toIso8601String().split('T').first;
    case 'randomInt':
      return random.nextInt(1000).toString();
    case 'randomFloat':
      return (random.nextDouble() * 1000).toStringAsFixed(2);
    case 'randomPrice':
      return (random.nextDouble() * 900 + 1).toStringAsFixed(2);
    case 'randomBoolean':
      return random.nextBool().toString();
    case 'randomFirstName':
      return _pick(_firstNames, random);
    case 'randomLastName':
      return _pick(_lastNames, random);
    case 'randomFullName':
      return '${_pick(_firstNames, random)} ${_pick(_lastNames, random)}';
    case 'randomEmail':
      return '${_pick(_firstNames, random).toLowerCase()}.'
          '${_pick(_lastNames, random).toLowerCase()}@example.com';
    case 'randomPhone':
      return '+1${List<int>.generate(10, (_) => random.nextInt(10)).join()}';
    case 'randomCity':
      return _pick(_cities, random);
    case 'randomCountry':
      return _pick(_countries, random);
    case 'randomCompany':
      return _pick(_companies, random);
    case 'randomWord':
      return _pick(_words, random);
    case 'randomSentence':
      return '${_pick(_words, random)} ${_pick(_words, random)} ${_pick(_words, random)}.';
    case 'randomColor':
      return _pick(_colors, random);
    case 'randomIp':
      return List<int>.generate(4, (_) => random.nextInt(255)).join('.');
    default:
      return '';
  }
}

dynamic _lookupBody(dynamic value, List<String> parts) {
  dynamic current = value;
  for (final part in parts) {
    if (current is Map) {
      current = current[part];
    } else if (current is List) {
      final index = int.tryParse(part);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}

String _stringify(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return jsonEncode(value);
}

/// 渲染 Mock 响应模板。未知占位符原样保留，便于发现拼写错误。
String renderMockTemplate(
  String template,
  MockTemplateContext context, {
  Random? random,
}) {
  if (!template.contains('{{')) return template;
  final rng = random ?? Random();
  dynamic bodyJson;
  var bodyParsed = false;
  return template.replaceAllMapped(RegExp(r'\{\{\s*([^{}]+?)\s*\}\}'), (match) {
    final token = match.group(1)!.trim();
    if (token.isEmpty) return match.group(0)!;
    if (token.startsWith(r'$')) {
      final value = _randomToken(token.substring(1), rng);
      return value.isEmpty ? match.group(0)! : value;
    }
    if (context.pathParams.containsKey(token)) return context.pathParams[token]!;
    if (token.startsWith('query.')) {
      return context.query[token.substring('query.'.length)] ?? '';
    }
    if (token.startsWith('header.')) {
      final name = token.substring('header.'.length).toLowerCase();
      for (final entry in context.headers.entries) {
        if (entry.key.toLowerCase() == name) return entry.value;
      }
      return '';
    }
    if (token.startsWith('body.')) {
      if (!bodyParsed) {
        bodyParsed = true;
        try {
          bodyJson = jsonDecode(context.body);
        } catch (_) {
          bodyJson = null;
        }
      }
      if (bodyJson == null) return '';
      return _stringify(_lookupBody(bodyJson, token.substring('body.'.length).split('.')));
    }
    return match.group(0)!;
  });
}

/* ------------------------------------------------------------------ */
/* 服务                                                               */
/* ------------------------------------------------------------------ */

/// 本地 Mock Server：按路由返回预置数据，支持随机数据占位符。
class MockServerService {
  HttpServer? _server;
  MockServerConfig _config = MockServerConfig();
  final List<MockHit> hits = [];
  void Function()? onChanged;
  String? lastError;

  bool get running => _server != null;
  int get port => _server?.port ?? _config.port;
  MockServerConfig get config => _config;

  static const int maxHits = 200;

  /// 启动服务；[port] 为 0 时由系统分配端口（测试用）。
  Future<String?> start(MockServerConfig config) async {
    if (_server != null) return null;
    _config = config;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, config.port);
      server.autoCompress = false;
      _server = server;
      lastError = null;
      server.listen(_handle, onError: (Object error) {
        lastError = '$error';
        onChanged?.call();
      });
      onChanged?.call();
      return null;
    } catch (error) {
      lastError = '$error';
      onChanged?.call();
      return lastError;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
    onChanged?.call();
  }

  /// 路由或端口在运行期间被修改时热更新。
  void update(MockServerConfig config) {
    _config = config;
  }

  void clearHits() {
    hits.clear();
    onChanged?.call();
  }

  Future<void> _handle(HttpRequest request) async {
    final stopwatch = Stopwatch()..start();
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final method = request.method.toUpperCase();
    final response = request.response;
    _applyCors(response);
    try {
      if (method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        await response.close();
        _record(startedAt, method, request.uri.path, HttpStatus.noContent, '', stopwatch, false);
        return;
      }
      final bodyBytes = await _readBody(request);
      final bodyText = utf8.decode(bodyBytes, allowMalformed: true);
      final match = matchMockRoute(_config.routes, method, request.uri.path);
      if (match == null) {
        response.statusCode = HttpStatus.notFound;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({
          'error': 'No mock route matched $method ${request.uri.path}',
          'routes': _config.routes
              .where((route) => route.enabled)
              .map((route) => '${route.method} ${route.path}')
              .toList(),
        }));
        await response.close();
        _record(startedAt, method, request.uri.path, HttpStatus.notFound, '', stopwatch, false);
        return;
      }
      final route = match.route;
      if (route.delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: route.delayMs.clamp(0, 60000)));
      }
      response.statusCode = route.status.clamp(100, 599);
      var hasContentType = false;
      for (final header in route.headers) {
        if (!header.on || header.k.trim().isEmpty) continue;
        if (header.k.toLowerCase() == 'content-type') hasContentType = true;
        try {
          response.headers.set(header.k.trim(), header.v);
        } catch (_) {
          // 忽略非法头，避免整个响应失败
        }
      }
      if (!hasContentType && route.body.trim().isNotEmpty) {
        response.headers.contentType = ContentType.json;
      }
      final requestHeaders = <String, String>{};
      request.headers.forEach((name, values) {
        requestHeaders[name] = values.join(', ');
      });
      final rendered = renderMockTemplate(
        route.body,
        MockTemplateContext(
          pathParams: match.pathParams,
          query: request.uri.queryParameters,
          headers: requestHeaders,
          body: bodyText,
        ),
      );
      if (method != 'HEAD' && rendered.isNotEmpty) response.write(rendered);
      await response.close();
      _record(
        startedAt,
        method,
        request.uri.path,
        response.statusCode,
        route.name,
        stopwatch,
        true,
      );
    } catch (error) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'error': 'Mock server error: $error'}));
        await response.close();
      } catch (_) {}
      _record(startedAt, method, request.uri.path, 500, '', stopwatch, false);
    }
  }

  Future<List<int>> _readBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > 4 * 1024 * 1024) break;
    }
    return builder.takeBytes();
  }

  void _applyCors(HttpResponse response) {
    response.headers.set('access-control-allow-origin', '*');
    response.headers.set('access-control-allow-methods', 'GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS');
    response.headers.set('access-control-allow-headers', '*');
    response.headers.set('access-control-expose-headers', '*');
  }

  void _record(
    int ts,
    String method,
    String path,
    int status,
    String routeName,
    Stopwatch stopwatch,
    bool matched,
  ) {
    hits.insert(
      0,
      MockHit(
        ts: ts,
        method: method,
        path: path,
        status: status,
        routeName: routeName,
        ms: stopwatch.elapsedMilliseconds,
        matched: matched,
      ),
    );
    if (hits.length > maxHits) hits.removeRange(maxHits, hits.length);
    onChanged?.call();
  }
}

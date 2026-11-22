import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models.dart';

class HttpFailure implements Exception {
  final String message;
  HttpFailure(this.message);
  @override
  String toString() => message;
}

String base64Utf8(String value) => base64Encode(utf8.encode(value));

String defaultCookiePath(String pathname) {
  final path = pathname.isEmpty ? '/' : pathname;
  if (!path.startsWith('/')) return '/';
  final index = path.lastIndexOf('/');
  return index <= 0 ? '/' : path.substring(0, index);
}

List<CookieEntry> parseSetCookie(String line, String requestUrl) {
  final parts = line.split(';');
  if (parts.isEmpty) return [];
  final first = parts.removeAt(0);
  final eq = first.indexOf('=');
  if (eq <= 0) return [];
  final name = first.substring(0, eq).trim();
  final value = first.substring(eq + 1).trim();
  if (name.isEmpty) return [];

  var host = '';
  var path = '/';
  final uri = Uri.tryParse(requestUrl);
  if (uri != null) {
    host = uri.host.toLowerCase();
    path = defaultCookiePath(uri.path);
  }

  var domain = host;
  var expires = 0;
  var secure = false;
  var httpOnly = false;

  for (final part in parts) {
    final index = part.indexOf('=');
    final key = (index < 0 ? part : part.substring(0, index)).trim().toLowerCase();
    final val = index < 0 ? '' : part.substring(index + 1).trim();
    if (key == 'domain' && val.isNotEmpty) {
      domain = val.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
    } else if (key == 'path' && val.startsWith('/')) {
      path = val;
    } else if (key == 'expires') {
      try {
        expires = HttpDate.parse(val).millisecondsSinceEpoch;
      } catch (_) {}
    } else if (key == 'max-age') {
      final seconds = int.tryParse(val);
      if (seconds != null) {
        expires = DateTime.now().millisecondsSinceEpoch + seconds * 1000;
      }
    } else if (key == 'secure') {
      secure = true;
    } else if (key == 'httponly') {
      httpOnly = true;
    }
  }

  return [
    CookieEntry(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expires: expires,
      secure: secure,
      httpOnly: httpOnly,
    ),
  ];
}

bool domainMatches(String host, String domain) =>
    host == domain || host.endsWith('.$domain');

bool pathMatches(String requestPath, String cookiePath) {
  if (cookiePath == '/' || requestPath == cookiePath) return true;
  if (!requestPath.startsWith(cookiePath)) return false;
  return cookiePath.endsWith('/') ||
      requestPath.substring(cookiePath.length).startsWith('/');
}

List<CookieEntry> cookiesForUrl(List<CookieEntry> jar, Uri uri) {
  final host = uri.host.toLowerCase();
  final path = uri.path.isEmpty ? '/' : uri.path;
  final now = DateTime.now().millisecondsSinceEpoch;
  return jar.where((cookie) {
    if (cookie.name.isEmpty) return false;
    if (cookie.expires > 0 && cookie.expires < now) return false;
    if (!domainMatches(host, cookie.domain)) return false;
    if (!pathMatches(path, cookie.path)) return false;
    if (cookie.secure && uri.scheme != 'https') return false;
    return true;
  }).toList();
}

void mergeCookies(List<CookieEntry> jar, List<CookieEntry> incoming) {
  final now = DateTime.now().millisecondsSinceEpoch;
  jar.removeWhere((cookie) => cookie.expires > 0 && cookie.expires < now);
  for (final item in incoming) {
    jar.removeWhere((cookie) =>
        cookie.name == item.name &&
        cookie.domain == item.domain &&
        cookie.path == item.path);
    if (item.expires > 0 && item.expires < now) continue;
    jar.add(item);
  }
}

class HttpService {
  Future<HttpResult> send({
    required String method,
    required String url,
    required Map<String, String> headers,
    required String body,
    required List<FormRow> multipart,
    required bool followRedirects,
    required bool rejectUnauthorized,
    required List<CookieEntry> cookies,
    void Function(List<CookieEntry>)? onCookies,
    Duration timeout = const Duration(seconds: 90),
    AppSettings? settings,
    Uint8List? rawBody,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      throw HttpFailure('Invalid request URL');
    }

    final client = _createClient(rejectUnauthorized, settings);
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client.openUrl(method.toUpperCase(), uri);
      request.followRedirects = followRedirects;
      request.persistentConnection = false;

      headers.forEach((key, value) {
        if (key.trim().isEmpty) return;
        try {
          request.headers.set(key.trim(), value);
        } catch (_) {}
      });

      final cookieHeader = cookiesForUrl(cookies, uri)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      if (cookieHeader.isNotEmpty && !headers.keys.any((k) => k.toLowerCase() == 'cookie')) {
        try {
          request.headers.set('cookie', cookieHeader);
        } catch (_) {}
      }

      final hasBody = method.toUpperCase() != 'GET' && method.toUpperCase() != 'HEAD';
      final boundary = '----AstraFormBoundary${Random().nextInt(1 << 32).toRadixString(16)}';

      if (hasBody) {
        Uint8List payload;
        if (rawBody != null) {
          payload = rawBody;
        } else if (multipart.any((row) => row.on && row.k.trim().isNotEmpty)) {
          payload = await _buildMultipart(multipart, boundary);
          request.headers.set(
            'content-type',
            'multipart/form-data; boundary=$boundary',
          );
        } else {
          payload = Uint8List.fromList(utf8.encode(body));
        }
        if (payload.isNotEmpty) {
          request.contentLength = payload.length;
          request.add(payload);
        }
      }

      final response = await request.close().timeout(timeout);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      stopwatch.stop();

      final headerMap = <String, List<String>>{};
      response.headers.forEach((name, values) {
        headerMap[name] = values;
      });

      final incoming = <CookieEntry>[];
      for (final line in response.headers['set-cookie'] ?? const <String>[]) {
        incoming.addAll(parseSetCookie(line, url));
      }
      if (incoming.isNotEmpty) {
        mergeCookies(cookies, incoming);
        onCookies?.call(incoming);
      }

      final contentType = response.headers.contentType;
      final grpc = (contentType?.mimeType ?? '').contains('application/grpc');
      return HttpResult(
        status: response.statusCode,
        reason: response.reasonPhrase,
        headers: headerMap,
        bytes: bytes,
        text: grpc ? decodeGrpcFrames(bytes) : _decodeText(bytes, contentType),
        ms: stopwatch.elapsedMilliseconds,
        size: bytes.length,
      );
    } on HttpFailure {
      rethrow;
    } on SocketException catch (err) {
      throw HttpFailure('Cannot connect: ${err.message}');
    } on HandshakeException catch (err) {
      throw HttpFailure('TLS handshake failed: ${err.message}');
    } on FormatException catch (err) {
      throw HttpFailure('Failed to resolve address: ${err.message}');
    } on TimeoutException {
      throw HttpFailure('Request timed out');
    } catch (err) {
      throw HttpFailure('Request failed: $err');
    } finally {
      client.close(force: true);
    }
  }

  /// 按全局设置创建 HttpClient：代理、客户端证书、TLS 校验。
  HttpClient _createClient(bool rejectUnauthorized, AppSettings? settings) {
    HttpClient client;
    if (settings != null && settings.hasClientCert) {
      final context = SecurityContext(withTrustedRoots: true);
      try {
        context.useCertificateChain(settings.certPath.trim());
        context.usePrivateKey(
          settings.keyPath.trim(),
          password: settings.keyPassword.isEmpty ? null : settings.keyPassword,
        );
      } catch (_) {
        // 证书无效时退回默认上下文，避免直接无法发起请求
      }
      client = HttpClient(context: context);
    } else {
      client = HttpClient();
    }
    client
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 15);

    final proxyUrl = settings?.proxyUrl.trim() ?? '';
    if (proxyUrl.isEmpty) {
      client.findProxy = (_) => 'DIRECT';
    } else {
      final bypass = (settings?.proxyBypass ?? '')
          .split(RegExp(r'[,\s]+'))
          .where((item) => item.trim().isNotEmpty)
          .map((item) => item.toLowerCase())
          .toList();
      final proxy = _proxyRule(proxyUrl);
      client.findProxy = (uri) {
        final host = uri.host.toLowerCase();
        for (final item in bypass) {
          if (host == item || host.endsWith('.$item')) return 'DIRECT';
        }
        return proxy;
      };
    }

    final verify = rejectUnauthorized && (settings?.verifyTls ?? true);
    if (!verify) {
      client.badCertificateCallback = (_, _, _) => true;
    }
    return client;
  }

  String _proxyRule(String raw) {
    final value = raw.trim();
    final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
    if (uri == null || uri.host.isEmpty) return 'DIRECT';
    if (uri.scheme == 'socks5' || uri.scheme == 'socks') {
      return 'SOCKS5 ${uri.host}:${uri.port}';
    }
    return 'PROXY ${uri.host}:${uri.port}';
  }

  /// 打开 SSE 事件流（GET + Accept: text/event-stream）。
  Future<SseSession> openEventStream({
    required String url,
    required Map<String, String> headers,
    bool rejectUnauthorized = true,
    Duration timeout = const Duration(seconds: 30),
    AppSettings? settings,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      throw HttpFailure('Invalid request URL');
    }
    final client = _createClient(rejectUnauthorized, settings);
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set('accept', 'text/event-stream');
      request.headers.set('cache-control', 'no-cache');
      headers.forEach((key, value) {
        try {
          request.headers.set(key, value);
        } catch (_) {}
      });
      final response = await request.close().timeout(timeout);
      final controller = StreamController<SseEvent>();
      final headerMap = <String, List<String>>{};
      response.headers.forEach((name, values) => headerMap[name] = values);

      var event = 'message';
      String data = '';
      String? lastId;
      late StreamSubscription<String> sub;
      sub = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.isEmpty) {
            if (data.isNotEmpty || event != 'message') {
              controller.add(SseEvent(event: event, data: data, id: lastId));
            }
            event = 'message';
            data = '';
            return;
          }
          if (line.startsWith(':')) return;
          final index = line.indexOf(':');
          final field = index < 0 ? line : line.substring(0, index);
          var value = index < 0 ? '' : line.substring(index + 1);
          if (value.startsWith(' ')) value = value.substring(1);
          switch (field) {
            case 'event':
              event = value;
              break;
            case 'data':
              data = data.isEmpty ? value : '$data\n$value';
              break;
            case 'id':
              lastId = value;
              break;
          }
        },
        onError: (Object err, StackTrace stack) {
          if (!controller.isClosed) controller.addError(err);
        },
        onDone: () {
          if (!controller.isClosed) controller.close();
        },
        cancelOnError: false,
      );

      return SseSession(
        status: response.statusCode,
        headers: headerMap,
        events: controller.stream,
        close: () async {
          await sub.cancel();
          client.close(force: true);
          if (!controller.isClosed) await controller.close();
        },
      );
    } catch (err) {
      client.close(force: true);
      throw HttpFailure('SSE connection failed: $err');
    }
  }

  String? _decodeText(Uint8List bytes, ContentType? contentType) {
    if (bytes.isEmpty) return '';
    final type = contentType?.mimeType.toLowerCase() ?? '';
    final looksText = type.contains('json') ||
        type.startsWith('text/') ||
        type.contains('xml') ||
        type.contains('javascript') ||
        type.contains('x-www-form-urlencoded') ||
        type.contains('graphql');
    if (!looksText) return null;

    var charset = contentType?.charset?.toLowerCase();
    if (charset == null) {
      final head = latin1.decode(bytes.take(2048).toList());
      final match = RegExp(r'charset=["]?([\w-]+)', caseSensitive: false).firstMatch(head);
      charset = match?.group(1)?.toLowerCase();
    }
    if (charset == 'latin1' || charset == 'iso-8859-1') {
      return latin1.decode(bytes);
    }
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  Future<Uint8List> _buildMultipart(List<FormRow> rows, String boundary) async {
    final builder = BytesBuilder(copy: false);
    void write(String text) => builder.add(utf8.encode(text));

    for (final row in rows) {
      if (!row.on || row.k.trim().isEmpty) continue;
      if (row.type == 'file') {
        final file = row.file;
        if (file == null || !file.usable) continue;
        final disk = File(file.path);
        if (!await disk.exists()) continue;
        final bytes = await disk.readAsBytes();
        final name = file.name.isEmpty ? disk.uri.pathSegments.last : file.name;
        write('--$boundary\r\n');
        write('Content-Disposition: form-data; name="${_quote(row.k)}"; '
            'filename="${_quote(name)}"\r\n');
        write('Content-Type: ${file.mime.isEmpty ? 'application/octet-stream' : file.mime}\r\n\r\n');
        builder.add(bytes);
        write('\r\n');
      } else {
        write('--$boundary\r\n');
        write('Content-Disposition: form-data; name="${_quote(row.k)}"\r\n\r\n');
        write(row.v);
        write('\r\n');
      }
    }
    write('--$boundary--\r\n');
    return builder.takeBytes();
  }

  String _quote(String value) => value.replaceAll('"', '%22').replaceAll('\r', '').replaceAll('\n', '');
}

/// 一个已建立的 SSE 会话，负责把事件推给 UI 并支持主动关闭。
class SseSession {
  final int status;
  final Map<String, List<String>> headers;
  final Stream<SseEvent> events;
  final Future<void> Function() close;

  SseSession({
    required this.status,
    required this.headers,
    required this.events,
    required this.close,
  });
}

/// 按 gRPC-Web 帧格式（1 字节标志 + 4 字节大端长度 + 载荷）构造请求体。
Uint8List encodeGrpcFrame(List<int> payload, {bool trailer = false}) {
  final frame = Uint8List(5 + payload.length);
  frame[0] = trailer ? 0x80 : 0x00;
  final length = payload.length;
  frame[1] = (length >> 24) & 0xff;
  frame[2] = (length >> 16) & 0xff;
  frame[3] = (length >> 8) & 0xff;
  frame[4] = length & 0xff;
  frame.setRange(5, frame.length, payload);
  return frame;
}

/// 解析 gRPC-Web 响应帧，输出可读文本（含 trailers 中的 grpc-status）。
String decodeGrpcFrames(Uint8List bytes) {
  final buffer = StringBuffer();
  var offset = 0;
  var index = 0;
  while (offset + 5 <= bytes.length) {
    index += 1;
    final trailer = (bytes[offset] & 0x80) != 0;
    final length = (bytes[offset + 1] << 24) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 8) |
        bytes[offset + 4];
    final start = offset + 5;
    final end = start + length;
    if (end > bytes.length || length < 0) break;
    final payload = bytes.sublist(start, end);
    buffer.writeln('— Frame $index · ${trailer ? 'trailer' : 'message'} · $length bytes —');
    if (trailer) {
      buffer.writeln(latin1.decode(payload, allowInvalid: true).trim());
    } else {
      final text = utf8.decode(payload, allowMalformed: true);
      final printable = text.runes.every((r) => r == 9 || r == 10 || r == 13 || r >= 32);
      buffer.writeln(printable && text.trim().isNotEmpty
          ? text
          : 'base64: ${base64Encode(payload)}');
    }
    buffer.writeln();
    offset = end;
  }
  if (offset < bytes.length) {
    buffer.writeln('[${bytes.length - offset} remaining bytes could not be parsed as gRPC frames]');
    buffer.writeln('base64: ${base64Encode(bytes.sublist(offset))}');
  }
  return buffer.isEmpty ? '(empty response)' : buffer.toString();
}

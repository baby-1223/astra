import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models.dart';
import 'mock_certs.dart';

/// 一次抓包记录。仅保存在内存中，不写入工作区文件。
class CaptureRecord {
  final String id;
  final int ts;
  final String method;
  final String url;
  final String host;
  final Map<String, String> requestHeaders;
  final String requestBody;
  final bool requestTruncated;
  final int? status;
  final Map<String, List<String>> responseHeaders;
  final String responseBody;
  final bool responseTruncated;
  final int durationMs;
  final int requestBytes;
  final int responseBytes;
  final String? error;
  final bool tunneled;

  CaptureRecord({
    required this.id,
    required this.ts,
    required this.method,
    required this.url,
    required this.host,
    this.requestHeaders = const {},
    this.requestBody = '',
    this.requestTruncated = false,
    this.status,
    this.responseHeaders = const {},
    this.responseBody = '',
    this.responseTruncated = false,
    this.durationMs = 0,
    this.requestBytes = 0,
    this.responseBytes = 0,
    this.error,
    this.tunneled = false,
  });

  bool get successful => error == null && (status == null || status! < 400);
}

/// 从 CONNECT 目标中解析主机和端口。
({String host, int port})? parseConnectTarget(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  // IPv6 字面量：[::1]:443
  if (value.startsWith('[')) {
    final end = value.indexOf(']');
    if (end < 0) return null;
    final host = value.substring(1, end);
    final port = end + 1 < value.length && value[end + 1] == ':'
        ? int.tryParse(value.substring(end + 2))
        : 443;
    if (port == null) return null;
    return (host: host, port: port);
  }
  final colon = value.lastIndexOf(':');
  if (colon <= 0) return (host: value, port: 443);
  final host = value.substring(0, colon);
  final port = int.tryParse(value.substring(colon + 1));
  if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
  return (host: host, port: port);
}

const Set<String> _hopByHopHeaders = {
  'connection',
  'proxy-connection',
  'keep-alive',
  'transfer-encoding',
  'te',
  'trailer',
  'upgrade',
  'proxy-authenticate',
  'proxy-authorization',
};

/// 本地抓包代理：HTTP 直接转发；HTTPS 通过本地 CA 做 MITM 解密。
///
/// 监听 127.0.0.1 的原始 TCP 端口，自解析 HTTP/1.1 报文，
/// 因此支持 IP 直连、CONNECT 隧道与 keep-alive 复用。
class CaptureProxyService {
  static const int defaultPort = 6791;
  static const int maxEntries = 300;
  static const int maxBodyCapture = 512 * 1024;
  static const int maxBodyForward = 20 * 1024 * 1024;

  ServerSocket? _server;
  HttpClient? _client;
  CertificateAuthority? _ca;
  final List<CaptureRecord> records = [];
  final Set<Socket> _sockets = {};
  int _seq = 0;

  /// 是否解密 HTTPS；关闭时只记录隧道元数据。
  bool mitmHttps = true;

  /// 上游证书校验失败时是否继续（调试自签名服务时开启）。
  bool allowInsecureUpstream = true;

  void Function()? onChanged;
  String? lastError;

  bool get running => _server != null;
  int get port => _server?.port ?? defaultPort;
  CertificateAuthority? get certificateAuthority => _ca;

  Future<String?> start({
    required CertificateAuthority ca,
    int port = defaultPort,
    bool mitmHttps = true,
    bool allowInsecureUpstream = true,
  }) async {
    if (_server != null) return null;
    _ca = ca;
    this.mitmHttps = mitmHttps;
    this.allowInsecureUpstream = allowInsecureUpstream;
    _client = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 15)
      ..autoUncompress = true;
    if (allowInsecureUpstream) {
      _client!.badCertificateCallback = ((_, __, ___) => true);
    }
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _server = server;
      lastError = null;
      server.listen(_accept, onError: (Object error) {
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
    if (server != null) await server.close();
    for (final socket in _sockets.toList()) {
      try {
        socket.destroy();
      } catch (_) {}
    }
    _sockets.clear();
    _client?.close(force: true);
    _client = null;
    onChanged?.call();
  }

  void clear() {
    records.clear();
    onChanged?.call();
  }

  void remove(String id) {
    records.removeWhere((item) => item.id == id);
    onChanged?.call();
  }

  String _nextId() {
    _seq += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_seq';
  }

  void _add(CaptureRecord record) {
    records.insert(0, record);
    if (records.length > maxEntries) records.removeRange(maxEntries, records.length);
    onChanged?.call();
  }

  void _accept(Socket socket) {
    _sockets.add(socket);
    unawaited(_serveConnection(socket));
  }

  Future<void> _serveConnection(Socket socket) async {
    final reader = _SocketReader(socket);
    try {
      while (true) {
        final head = await reader.readHeaderBlock();
        if (head == null || head.isEmpty) break;
        final parsed = _ParsedHead.parse(head);
        if (parsed == null) break;
        if (parsed.method == 'CONNECT') {
          await _handleConnect(socket, reader, parsed);
          return;
        }
        final keepAlive = await _forwardPlain(socket, reader, parsed);
        if (!keepAlive) break;
      }
    } catch (_) {
      // 客户端断开或报文异常，结束连接
    } finally {
      reader.destroy();
      try {
        socket.destroy();
      } catch (_) {}
      _sockets.remove(socket);
    }
  }

  Future<bool> _forwardPlain(
    Socket socket,
    _SocketReader reader,
    _ParsedHead parsed,
  ) async {
    final stopwatch = Stopwatch()..start();
    final started = DateTime.now().millisecondsSinceEpoch;
    final host = parsed.headers['host'] ?? 'localhost';
    final uri = _resolveTarget(parsed.target, host);
    final headers = _forwardHeaders(parsed.headers);
    Uint8List requestBody;
    try {
      requestBody = await _readBodyFor(reader, parsed);
    } on FormatException catch (error) {
      await _writeSimple(socket, 400, 'Bad request: ${error.message}');
      return false;
    }
    if (requestBody.length >= maxBodyForward) {
      await _writeSimple(socket, 413, 'Request body exceeds ${maxBodyForward ~/ (1024 * 1024)} MB');
      return false;
    }
    final keepAlive = _clientKeepAlive(parsed);
    try {
      final upstream = _client!;
      final outbound = await upstream.openUrl(parsed.method, uri).timeout(const Duration(seconds: 30));
      outbound.followRedirects = false;
      outbound.persistentConnection = false;
      headers.forEach((name, value) {
        try {
          outbound.headers.set(name, value);
        } catch (_) {}
      });
      if (requestBody.isNotEmpty) outbound.add(requestBody);
      final response = await outbound.close().timeout(const Duration(seconds: 60));
      final body = await _collect(response);
      final responseHeaders = <String, List<String>>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values;
      });
      await _writeResponse(
        socket,
        response.statusCode,
        response.reasonPhrase,
        responseHeaders,
        body.bytes,
        keepAlive,
      );
      _add(CaptureRecord(
        id: _nextId(),
        ts: started,
        method: parsed.method,
        url: uri.toString(),
        host: uri.host,
        requestHeaders: headers,
        requestBody: utf8.decode(requestBody, allowMalformed: true),
        requestTruncated: requestBody.length >= maxBodyCapture,
        status: response.statusCode,
        responseHeaders: responseHeaders,
        responseBody: utf8.decode(body.bytes, allowMalformed: true),
        responseTruncated: body.truncated,
        durationMs: stopwatch.elapsedMilliseconds,
        requestBytes: requestBody.length,
        responseBytes: body.bytes.length,
      ));
      return keepAlive;
    } catch (error) {
      await _writeSimple(socket, 502, 'Proxy upstream error: $error');
      _add(CaptureRecord(
        id: _nextId(),
        ts: started,
        method: parsed.method,
        url: uri.toString(),
        host: uri.host,
        requestHeaders: headers,
        requestBody: utf8.decode(requestBody, allowMalformed: true),
        requestTruncated: requestBody.length >= maxBodyCapture,
        durationMs: stopwatch.elapsedMilliseconds,
        requestBytes: requestBody.length,
        error: '$error',
      ));
      return false;
    }
  }

  Future<void> _handleConnect(
    Socket socket,
    _SocketReader reader,
    _ParsedHead parsed,
  ) async {
    final stopwatch = Stopwatch()..start();
    final started = DateTime.now().millisecondsSinceEpoch;
    final target = parseConnectTarget(parsed.target);
    if (target == null) {
      _add(CaptureRecord(
        id: _nextId(),
        ts: started,
        method: 'CONNECT',
        url: parsed.target,
        host: parsed.target,
        durationMs: 0,
        error: 'Invalid CONNECT target',
      ));
      await _writeSimple(socket, 400, 'Invalid CONNECT target');
      return;
    }
    final portSuffix = target.port == 443 ? '' : ':${target.port}';
    final displayUrl = 'https://${target.host}$portSuffix';
    socket.add(utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
    await socket.flush();
    if (!mitmHttps) {
      await _tunnel(socket, reader, target, displayUrl, started, stopwatch);
      return;
    }
    try {
      final secure = await SecureSocket.secureServer(
        socket,
        _ca!.serverContextFor(target.host),
        supportedProtocols: const ['http/1.1'],
      ).timeout(const Duration(seconds: 20));
      _sockets.add(secure);
      await _serveTls(secure, reader, target, displayUrl, started);
    } on HandshakeException catch (error) {
      _add(CaptureRecord(
        id: _nextId(),
        ts: started,
        method: 'CONNECT',
        url: displayUrl,
        host: target.host,
        durationMs: stopwatch.elapsedMilliseconds,
        error: 'TLS handshake failed. Trust the Astra CA certificate in your client and retry. ($error)',
      ));
    } catch (error) {
      _add(CaptureRecord(
        id: _nextId(),
        ts: started,
        method: 'CONNECT',
        url: displayUrl,
        host: target.host,
        durationMs: stopwatch.elapsedMilliseconds,
        error: '$error',
      ));
    }
  }

  Future<void> _tunnel(
    Socket client,
    _SocketReader reader,
    ({String host, int port}) target,
    String displayUrl,
    int started,
    Stopwatch stopwatch,
  ) async {
    var uploaded = 0;
    var downloaded = 0;
    Socket? upstream;
    final closed = Completer<void>();
    try {
      upstream = await Socket.connect(target.host, target.port)
          .timeout(const Duration(seconds: 15));
      void finish() {
        if (!closed.isCompleted) closed.complete();
      }

      reader.pipeTo((data) {
        uploaded += data.length;
        upstream!.add(data);
      }, onDone: () {
        upstream?.destroy();
        finish();
      });
      upstream.listen(
        (data) {
          downloaded += data.length;
          client.add(data);
        },
        onDone: () {
          client.destroy();
          finish();
        },
        onError: (_) {
          client.destroy();
          finish();
        },
        cancelOnError: true,
      );
      await closed.future;
      _add(CaptureRecord(
        id: _nextId(),
        ts: started,
        method: 'CONNECT',
        url: displayUrl,
        host: target.host,
        durationMs: stopwatch.elapsedMilliseconds,
        requestBytes: uploaded,
        responseBytes: downloaded,
        tunneled: true,
      ));
    } catch (error) {
      _add(CaptureRecord(
        id: _nextId(),
        ts: started,
        method: 'CONNECT',
        url: displayUrl,
        host: target.host,
        durationMs: stopwatch.elapsedMilliseconds,
        error: '$error',
      ));
      upstream?.destroy();
      client.destroy();
    }
  }

  Future<void> _serveTls(
    SecureSocket secure,
    _SocketReader rawReader,
    ({String host, int port}) target,
    String displayUrl,
    int started,
  ) async {
    final reader = _SocketReader(secure);
    try {
      while (true) {
        final head = await reader.readHeaderBlock();
        if (head == null || head.isEmpty) break;
        final parsed = _ParsedHead.parse(head);
        if (parsed == null) break;
        final stopwatch = Stopwatch()..start();
        final url = '$displayUrl'
            '${parsed.target.startsWith('/') ? '' : '/'}${parsed.target}';
        final headers = _forwardHeaders(parsed.headers);
        Uint8List requestBody;
        try {
          requestBody = await _readBodyFor(reader, parsed);
        } on FormatException catch (error) {
          await _writeSimple(secure, 400, 'Bad request: ${error.message}');
          break;
        }
        if (requestBody.length >= maxBodyForward) {
          await _writeSimple(secure, 413, 'Request body exceeds ${maxBodyForward ~/ (1024 * 1024)} MB');
          break;
        }
        final keepAlive = _clientKeepAlive(parsed);
        try {
          final upstream = _client!;
          final outbound = await upstream
              .openUrl(parsed.method, Uri.parse(url))
              .timeout(const Duration(seconds: 30));
          outbound.followRedirects = false;
          outbound.persistentConnection = false;
          headers.forEach((name, value) {
            try {
              outbound.headers.set(name, value);
            } catch (_) {}
          });
          if (requestBody.isNotEmpty) outbound.add(requestBody);
          final response = await outbound.close().timeout(const Duration(seconds: 60));
          final body = await _collect(response);
          final responseHeaders = <String, List<String>>{};
          response.headers.forEach((name, values) {
            responseHeaders[name] = values;
          });
          await _writeResponse(
            secure,
            response.statusCode,
            response.reasonPhrase,
            responseHeaders,
            body.bytes,
            keepAlive,
          );
          _add(CaptureRecord(
            id: _nextId(),
            ts: started,
            method: parsed.method,
            url: url,
            host: target.host,
            requestHeaders: headers,
            requestBody: utf8.decode(requestBody, allowMalformed: true),
            requestTruncated: requestBody.length >= maxBodyCapture,
            status: response.statusCode,
            responseHeaders: responseHeaders,
            responseBody: utf8.decode(body.bytes, allowMalformed: true),
            responseTruncated: body.truncated,
            durationMs: stopwatch.elapsedMilliseconds,
            requestBytes: requestBody.length,
            responseBytes: body.bytes.length,
          ));
          if (!keepAlive) break;
        } catch (error) {
          await _writeSimple(secure, 502, 'Proxy upstream error: $error');
          _add(CaptureRecord(
            id: _nextId(),
            ts: started,
            method: parsed.method,
            url: url,
            host: target.host,
            requestHeaders: headers,
            requestBody: utf8.decode(requestBody, allowMalformed: true),
            durationMs: stopwatch.elapsedMilliseconds,
            requestBytes: requestBody.length,
            error: '$error',
          ));
          break;
        }
      }
    } catch (_) {
      // 客户端提前断开或读取失败
    } finally {
      reader.destroy();
      rawReader.destroy();
      try {
        secure.destroy();
      } catch (_) {}
    }
  }

  Uri _resolveTarget(String target, String hostHeader) {
    final absolute = Uri.tryParse(target);
    if (absolute != null && absolute.hasScheme && absolute.host.isNotEmpty) {
      return absolute;
    }
    if (target.startsWith('/')) return Uri.parse('http://$hostHeader$target');
    return Uri.parse('http://$hostHeader/$target');
  }

  Map<String, String> _forwardHeaders(Map<String, String> source) {
    final headers = <String, String>{};
    source.forEach((name, value) {
      final lower = name.toLowerCase();
      if (_hopByHopHeaders.contains(lower) ||
          lower == 'host' ||
          lower == 'content-length' ||
          lower == 'proxy-authorization') {
        return;
      }
      headers[name] = value;
    });
    return headers;
  }

  bool _clientKeepAlive(_ParsedHead parsed) {
    final connection = (parsed.headers['connection'] ?? '').toLowerCase();
    if (connection.contains('close')) return false;
    if (parsed.version == 'HTTP/1.0') return connection.contains('keep-alive');
    return true;
  }

  Future<void> _writeResponse(
    Socket socket,
    int status,
    String reason,
    Map<String, List<String>> headers,
    Uint8List body,
    bool keepAlive,
  ) async {
    final buffer = StringBuffer('HTTP/1.1 $status ${reason.isEmpty ? _reasonFor(status) : reason}\r\n');
    headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (_hopByHopHeaders.contains(lower) ||
          lower == 'content-length' ||
          lower == 'content-encoding') {
        return;
      }
      for (final value in values) {
        buffer.write('$name: $value\r\n');
      }
    });
    buffer.write('content-length: ${body.length}\r\n');
    buffer.write('connection: ${keepAlive ? 'keep-alive' : 'close'}\r\n\r\n');
    socket.add(latin1.encode(_latin1Safe(buffer.toString())));
    socket.add(body);
    await socket.flush();
    if (!keepAlive) {
      await socket.close();
    }
  }

  Future<void> _writeSimple(Socket socket, int status, String message) async {
    final body = utf8.encode(jsonEncode({'error': message}));
    await _writeResponse(
      socket,
      status,
      _reasonFor(status),
      {
        'content-type': ['application/json; charset=utf-8']
      },
      Uint8List.fromList(body),
      false,
    );
  }

  String _latin1Safe(String value) =>
      String.fromCharCodes(value.codeUnits.map((unit) => unit > 0xFF ? 63 : unit));

  String _reasonFor(int status) {
    switch (status) {
      case 200:
        return 'OK';
      case 400:
        return 'Bad Request';
      case 413:
        return 'Payload Too Large';
      case 502:
        return 'Bad Gateway';
      default:
        return '';
    }
  }

  Future<Uint8List> _readBodyFor(_SocketReader reader, _ParsedHead parsed) async {
    final transfer = (parsed.headers['transfer-encoding'] ?? '').toLowerCase();
    if (transfer.contains('chunked')) {
      final builder = BytesBuilder(copy: false);
      while (true) {
        final line = await reader.readLine();
        if (line == null) throw const FormatException('Unexpected end of chunked body');
        final size = int.tryParse(line.split(';').first.trim(), radix: 16);
        if (size == null || size < 0) throw const FormatException('Invalid chunk size');
        if (size == 0) {
          while (true) {
            final trailer = await reader.readLine();
            if (trailer == null || trailer.isEmpty) break;
          }
          break;
        }
        final chunk = await reader.readExact(size);
        builder.add(chunk);
        await reader.readExact(2);
        if (builder.length > maxBodyForward) break;
      }
      return builder.takeBytes();
    }
    final length = int.tryParse(parsed.headers['content-length'] ?? '') ?? 0;
    if (length <= 0) return Uint8List(0);
    final capped = length.clamp(0, maxBodyForward);
    return reader.readExact(capped);
  }

  Future<({Uint8List bytes, bool truncated})> _collect(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    var truncated = false;
    await for (final chunk in response) {
      if (builder.length < maxBodyCapture) {
        final remaining = maxBodyCapture - builder.length;
        if (chunk.length > remaining) {
          builder.add(chunk.sublist(0, remaining));
          truncated = true;
        } else {
          builder.add(chunk);
        }
      } else {
        truncated = true;
      }
    }
    return (bytes: builder.takeBytes(), truncated: truncated);
  }
}

class _ParsedHead {
  final String method;
  final String target;
  final String version;
  final Map<String, String> headers;

  _ParsedHead(this.method, this.target, this.version, this.headers);

  static _ParsedHead? parse(Uint8List raw) {
    final text = latin1.decode(raw, allowInvalid: true);
    final lines = text.split('\r\n');
    if (lines.isEmpty) return null;
    final parts = lines.first.split(' ');
    if (parts.length < 2) return null;
    final headers = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      headers[name] = headers.containsKey(name) ? '${headers[name]}, $value' : value;
    }
    return _ParsedHead(parts[0].toUpperCase(), parts[1], parts.length > 2 ? parts[2] : 'HTTP/1.1', headers);
  }
}

/// 在 Socket 上按需读取 HTTP 报文，支持 keep-alive 复用与隧道转发。
class _SocketReader {
  final Socket _socket;
  final List<int> _buffer = [];
  StreamSubscription<Uint8List>? _subscription;
  bool _closed = false;
  final List<Completer<void>> _waiters = [];
  void Function(Uint8List data)? _pipeSink;
  void Function()? _onPipeDone;

  _SocketReader(this._socket) {
    _subscription = _socket.listen((data) {
      final sink = _pipeSink;
      if (sink != null) {
        sink(data);
        return;
      }
      _buffer.addAll(data);
      _wake();
    }, onDone: () {
      _closed = true;
      _wake();
      _onPipeDone?.call();
    }, onError: (_) {
      _closed = true;
      _wake();
      _onPipeDone?.call();
    }, cancelOnError: true);
  }

  void pipeTo(void Function(Uint8List data) sink, {void Function()? onDone}) {
    _pipeSink = sink;
    _onPipeDone = onDone;
    if (_buffer.isNotEmpty) {
      sink(Uint8List.fromList(_buffer));
      _buffer.clear();
    }
  }

  void _wake() {
    final waiters = List<Completer<void>>.from(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Future<void> _wait() {
    if (_closed) return Future<void>.value();
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  Future<Uint8List?> readHeaderBlock() async {
    while (true) {
      final end = _indexOfDoubleCrlf();
      if (end >= 0) {
        final result = Uint8List.fromList(_buffer.sublist(0, end));
        _buffer.removeRange(0, end + 4);
        return result;
      }
      if (_buffer.length > 256 * 1024) {
        throw const FormatException('Request headers are too large');
      }
      if (_closed) {
        if (_buffer.isEmpty) return null;
        final result = Uint8List.fromList(_buffer);
        _buffer.clear();
        return result;
      }
      await _wait();
    }
  }

  Future<Uint8List> readExact(int length) async {
    while (_buffer.length < length) {
      if (_closed) throw const FormatException('Connection closed while reading body');
      await _wait();
    }
    final result = Uint8List.fromList(_buffer.sublist(0, length));
    _buffer.removeRange(0, length);
    return result;
  }

  Future<String?> readLine() async {
    while (true) {
      final index = _indexOfCrlf();
      if (index >= 0) {
        final line = latin1.decode(_buffer.sublist(0, index), allowInvalid: true);
        _buffer.removeRange(0, index + 2);
        return line;
      }
      if (_closed) return _buffer.isEmpty ? null : latin1.decode(_buffer, allowInvalid: true);
      await _wait();
    }
  }

  int _indexOfCrlf() {
    for (var i = 0; i + 1 < _buffer.length; i++) {
      if (_buffer[i] == 13 && _buffer[i + 1] == 10) return i;
    }
    return -1;
  }

  int _indexOfDoubleCrlf() {
    for (var i = 0; i + 3 < _buffer.length; i++) {
      if (_buffer[i] == 13 &&
          _buffer[i + 1] == 10 &&
          _buffer[i + 2] == 13 &&
          _buffer[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  void destroy() {
    _pipeSink = null;
    _onPipeDone = null;
    _subscription?.cancel();
    _subscription = null;
  }
}

/// 把抓到的请求转换成可直接打开的请求对象。
ApiRequest requestFromCapture(CaptureRecord record) {
  final headers = <KV>[];
  record.requestHeaders.forEach((name, value) {
    headers.add(KV(on: true, k: name, v: value));
  });
  if (headers.isEmpty) headers.add(KV());
  final hasBody = record.requestBody.trim().isNotEmpty;
  return ApiRequest(
    method: record.method,
    url: record.url,
    headers: headers,
    bodyMode: hasBody ? 'json' : 'none',
    body: record.requestBody,
  );
}

/// 根据抓包记录生成 Mock 路由默认值。
MockRoute mockRouteFromCapture(CaptureRecord record) {
  final uri = Uri.tryParse(record.url);
  final path = uri == null || uri.path.isEmpty ? '/' : uri.path;
  return MockRoute(
    name: '${record.method} $path',
    method: record.method == 'CONNECT' ? 'GET' : record.method,
    path: path,
    status: record.status != null && record.status! >= 100 ? record.status! : 200,
    body: record.responseBody,
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// OAuth 2.0 授权码 + PKCE 支持。授权流程会启动本地回调服务并打开系统浏览器。
class OAuthTokenResult {
  final String? token;
  final String? refreshToken;
  final int expiresAt;
  final String? error;

  const OAuthTokenResult({
    this.token,
    this.refreshToken,
    this.expiresAt = 0,
    this.error,
  });
}

class OAuthService {
  /// 执行 Authorization Code（可选 PKCE）流程。
  Future<OAuthTokenResult> authorizationCode({
    required String authUrl,
    required String tokenUrl,
    required String clientId,
    String clientSecret = '',
    String scope = '',
    bool pkce = true,
    int port = 8765,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    if (authUrl.trim().isEmpty) {
      return const OAuthTokenResult(error: '请先填写 Authorization 端点');
    }
    if (tokenUrl.trim().isEmpty) {
      return const OAuthTokenResult(error: '请先填写 Token 端点');
    }

    final verifier = pkce ? _randomString(64) : '';
    final challenge = pkce ? _challenge(verifier) : '';
    final redirectUri = 'http://127.0.0.1:$port/callback';

    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      return OAuthTokenResult(error: '本地回调端口 $port 已被占用，请修改端口后重试');
    }

    final completer = Completer<Map<String, String>>();
    server.listen((request) async {
      final params = request.uri.queryParameters;
      request.response
        ..headers.contentType = ContentType.html
        ..write(
          '<html><head><meta charset="utf-8"><title>Astra 授权</title></head>'
          '<body style="font-family:-apple-system;background:#0b0f17;color:#e6edf7;'
          'display:flex;align-items:center;justify-content:center;height:100vh">'
          '<div style="text-align:center"><h2>Astra 授权完成</h2>'
          '<p style="color:#8a97ad">可以关闭此页面并回到 Astra。</p></div></body></html>',
        );
      await request.response.close();
      if (!completer.isCompleted) completer.complete(params);
    });

    final query = <String, String>{
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
    };
    if (scope.trim().isNotEmpty) query['scope'] = scope.trim();
    if (pkce) {
      query['code_challenge'] = challenge;
      query['code_challenge_method'] = 'S256';
    }
    final separator = authUrl.contains('?') ? '&' : '?';
    final url = '$authUrl$separator${query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';

    await _openBrowser(url);

    Map<String, String> params;
    try {
      params = await completer.future.timeout(timeout);
    } on TimeoutException {
      await server.close(force: true);
      return const OAuthTokenResult(error: '等待授权超时，请重新发起授权');
    } finally {
      await server.close(force: true);
    }

    if (params['error'] != null) {
      return OAuthTokenResult(error: '授权失败：${params['error']} ${params['error_description'] ?? ''}');
    }
    final code = params['code'] ?? '';
    if (code.isEmpty) return const OAuthTokenResult(error: '回调中未获取到授权码');

    return _requestToken(
      tokenUrl: tokenUrl,
      fields: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': clientId,
        if (clientSecret.trim().isNotEmpty) 'client_secret': clientSecret.trim(),
        if (pkce) 'code_verifier': verifier,
      },
    );
  }

  /// 使用 refresh_token 换新的 access_token。
  Future<OAuthTokenResult> refresh({
    required String tokenUrl,
    required String refreshToken,
    required String clientId,
    String clientSecret = '',
  }) async {
    if (tokenUrl.trim().isEmpty || refreshToken.trim().isEmpty) {
      return const OAuthTokenResult(error: '缺少 Token 端点或 refresh_token');
    }
    return _requestToken(
      tokenUrl: tokenUrl,
      fields: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken.trim(),
        'client_id': clientId,
        if (clientSecret.trim().isNotEmpty) 'client_secret': clientSecret.trim(),
      },
    );
  }

  Future<OAuthTokenResult> clientCredentials({
    required String tokenUrl,
    required String clientId,
    String clientSecret = '',
    String scope = '',
    String? username,
    String? password,
  }) async {
    return _requestToken(
      tokenUrl: tokenUrl,
      fields: {
        'grant_type': username == null ? 'client_credentials' : 'password',
        'client_id': clientId,
        if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
        if (scope.isNotEmpty) 'scope': scope,
        if (username != null) 'username': username,
        if (username != null) 'password': password ?? '',
      },
    );
  }

  Future<OAuthTokenResult> _requestToken({
    required String tokenUrl,
    required Map<String, String> fields,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(Uri.parse(tokenUrl));
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      request.write(fields.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'));
      final response = await request.close().timeout(const Duration(seconds: 30));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        return OAuthTokenResult(
          error: '获取 Token 失败（HTTP ${response.statusCode}）：${_short(text)}',
        );
      }
      final dynamic data = jsonDecode(text);
      if (data is! Map) return const OAuthTokenResult(error: 'Token 响应不是 JSON 对象');
      final token = '${data['access_token'] ?? ''}';
      if (token.isEmpty) {
        return OAuthTokenResult(error: '响应中没有 access_token：${_short(text)}');
      }
      final expiresIn = int.tryParse('${data['expires_in'] ?? 0}') ?? 0;
      return OAuthTokenResult(
        token: token,
        refreshToken: '${data['refresh_token'] ?? ''}',
        expiresAt: expiresIn > 0
            ? DateTime.now().millisecondsSinceEpoch + expiresIn * 1000
            : 0,
      );
    } catch (err) {
      return OAuthTokenResult(error: '获取 Token 失败：$err');
    } finally {
      client.close(force: true);
    }
  }

  String _short(String text) => text.length > 240 ? '${text.substring(0, 240)}…' : text;

  Future<void> _openBrowser(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {
      // 打开浏览器失败时仍等待用户手动访问
    }
  }

  static const String _chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  String _randomString(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => _chars[random.nextInt(_chars.length)]).join();
  }

  String _challenge(String verifier) =>
      base64Url.encode(sha256(utf8.encode(verifier))).replaceAll('=', '');

  /// 纯 Dart 的 SHA-256，避免为 PKCE 引入额外依赖。
  Uint8List sha256(List<int> input) {
    const k = <int>[
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

    final bytes = List<int>.from(input);
    final bitLength = bytes.length * 8;
    bytes.add(0x80);
    while (bytes.length % 64 != 56) {
      bytes.add(0);
    }
    for (var i = 7; i >= 0; i--) {
      bytes.add((bitLength >> (i * 8)) & 0xff);
    }

    final w = List<int>.filled(64, 0);
    for (var chunk = 0; chunk < bytes.length; chunk += 64) {
      for (var i = 0; i < 16; i++) {
        final base = chunk + i * 4;
        w[i] = (bytes[base] << 24) |
            (bytes[base + 1] << 16) |
            (bytes[base + 2] << 8) |
            bytes[base + 3];
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;
        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }
      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    final out = Uint8List(32);
    for (final (index, value) in [h0, h1, h2, h3, h4, h5, h6, h7].indexed) {
      out[index * 4] = (value >> 24) & 0xff;
      out[index * 4 + 1] = (value >> 16) & 0xff;
      out[index * 4 + 2] = (value >> 8) & 0xff;
      out[index * 4 + 3] = value & 0xff;
    }
    return out;
  }

  int _rotr(int value, int bits) =>
      ((value >> bits) | (value << (32 - bits))) & 0xffffffff;
}

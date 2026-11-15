import 'dart:async';
import 'dart:io';

class WsService {
  WebSocket? _socket;
  HttpClient? _client;
  StreamSubscription<dynamic>? _subscription;
  bool _manualClose = false;

  bool get connected => _socket != null;

  Future<void> connect({
    required String url,
    required Map<String, String> headers,
    required String subprotocol,
    required bool verify,
    required void Function() onOpen,
    required void Function(dynamic data) onMessage,
    required void Function(String reason) onClose,
    required void Function(String message) onError,
  }) async {
    await close();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..findProxy = (_) => 'DIRECT';
    if (!verify) {
      client.badCertificateCallback = (_, _, _) => true;
    }
    _client = client;

    _manualClose = false;
    try {
      final protocols = subprotocol
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      final socket = await WebSocket.connect(
        url,
        headers: headers,
        protocols: protocols.isEmpty ? null : protocols,
        customClient: client,
      ).timeout(const Duration(seconds: 20));
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 25);
      _subscription = socket.listen(
        (data) {
          onMessage(data);
        },
        onError: (Object err) {
          onError('$err');
        },
        onDone: () {
          final wasManual = _manualClose;
          _socket = null;
          _subscription = null;
          _client?.close(force: true);
          _client = null;
          onClose(wasManual ? '连接已关闭' : '连接被对端关闭');
        },
        cancelOnError: true,
      );
      onOpen();
    } catch (err) {
      _client = null;
      client.close(force: true);
      throw Exception('连接失败：$err');
    }
  }

  void send(String text) {
    final socket = _socket;
    if (socket == null) throw Exception('尚未建立连接');
    socket.add(text);
  }

  Future<void> close() async {
    _manualClose = true;
    final socket = _socket;
    _socket = null;
    await _subscription?.cancel();
    _subscription = null;
    if (socket != null) {
      try {
        await socket.close(WebSocketStatus.normalClosure);
      } catch (_) {}
    }
    _client?.close(force: true);
    _client = null;
  }
}

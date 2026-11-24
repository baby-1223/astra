part of '../state.dart';

/// WebSocket 会话：连接、收发与日志。
mixin _WsSession on ChangeNotifier {
  WsService get wsService;
  WsConfig get ws;
  String get wsState;
  set wsState(String value);
  String? get wsError;
  set wsError(String? value);
  List<WsMessage> get wsLog;
  int get wsSent;
  set wsSent(int value);
  int get wsReceived;
  set wsReceived(int value);
  List<HistoryEntry> get history;
  set history(List<HistoryEntry> value);
  String resolve(String input);
  String _nameFromUrl(String url);
  void _schedulePersist();

  Future<void> connectWs() async {
    if (wsState != 'idle') return;
    var url = resolve(ws.url).trim();
    if (url.isEmpty) {
      _wsSystem('Enter a WebSocket URL');
      return;
    }
    if (!RegExp(r'^wss?://', caseSensitive: false).hasMatch(url)) {
      url = 'ws://$url';
    }
    final headers = <String, String>{};
    for (final item in ws.headers) {
      if (item.on && item.k.trim().isNotEmpty) {
        headers[item.k.trim()] = resolve(item.v);
      }
    }
    wsState = 'connecting';
    wsError = null;
    _wsSystem('Connecting to $url');
    notifyListeners();
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    void pushWsHistory(int? status) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - startedAt;
      history.insert(
        0,
        HistoryEntry(
          mode: 'ws',
          name: _nameFromUrl(url),
          method: 'WS',
          url: url,
          status: status,
          ms: elapsed,
          wsSnapshot: ws.copy(),
        ),
      );
      if (history.length > 80) history = history.sublist(0, 80);
      _schedulePersist();
    }

    try {
      await wsService.connect(
        url: url,
        headers: headers,
        subprotocol: ws.subprotocol,
        verify: ws.verify,
        onOpen: () {
          wsState = 'open';
          _wsSystem('Connection established');
          pushWsHistory(101);
          notifyListeners();
          _schedulePersist();
        },
        onMessage: (data) {
          wsReceived += 1;
          if (data is String) {
            wsLog.add(WsMessage(data, time: DateTime.now()));
          } else if (data is List<int>) {
            wsLog.add(WsMessage(
              '[Binary ${data.length} bytes] ${utf8.decode(data, allowMalformed: true)}',
              time: DateTime.now(),
            ));
          } else {
            wsLog.add(WsMessage('$data', time: DateTime.now()));
          }
          notifyListeners();
        },
        onClose: (reason) {
          wsState = 'idle';
          _wsSystem(reason);
          notifyListeners();
        },
        onError: (message) {
          wsError = message;
          _wsSystem('Error: $message');
          pushWsHistory(null);
          notifyListeners();
        },
      );
    } catch (err) {
      wsState = 'idle';
      wsError = '$err';
      _wsSystem('$err');
      pushWsHistory(null);
      notifyListeners();
    }
  }

  Future<void> disconnectWs() async {
    await wsService.close();
    wsState = 'idle';
    _wsSystem('Disconnected');
    notifyListeners();
  }

  void sendWs(String text) {
    if (wsState != 'open') {
      _wsSystem('Not connected');
      return;
    }
    try {
      wsService.send(text);
      wsSent += 1;
      wsLog.add(WsMessage(text, outgoing: true));
      notifyListeners();
    } catch (err) {
      _wsSystem('Failed to send: $err');
      notifyListeners();
    }
  }

  void clearWsLog() {
    wsLog.clear();
    wsSent = 0;
    wsReceived = 0;
    notifyListeners();
  }

  void _wsSystem(String text) {
    wsLog.add(WsMessage(text, system: true));
  }
}

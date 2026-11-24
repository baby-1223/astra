part of '../state.dart';

/// Mock Server 与本地抓包代理的状态、持久化和 UI 动作。
mixin _TrafficTools on ChangeNotifier {
  Storage get storage;
  String get mode;
  void switchMode(String mode);
  void showToast(String message);
  void schedulePersist();
  void openLooseRequest(ApiRequest request, String name);

  MockServerConfig mockServer = MockServerConfig();
  final MockServerService mockServerService = MockServerService();
  final CaptureProxyService captureProxy = CaptureProxyService();

  CertificateAuthority? captureCertificateAuthority;
  bool captureCaLoading = false;
  String? mockServerError;
  String? captureProxyError;

  bool get mockServerRunning => mockServerService.running;
  bool get captureProxyRunning => captureProxy.running;

  void initTrafficTools() {
    mockServerService.onChanged = notifyListeners;
    captureProxy.onChanged = notifyListeners;
  }

  /* -------------------------- Mock Server -------------------------- */

  Future<void> startMockServer() async {
    mockServerError = await mockServerService.start(mockServer);
    if (mockServerError == null) {
      showToast('Mock server listening on http://127.0.0.1:${mockServerService.port}');
    } else {
      showToast('Mock server failed: $mockServerError');
    }
    notifyListeners();
  }

  Future<void> stopMockServer() async {
    await mockServerService.stop();
    notifyListeners();
  }

  void setMockPort(int port) {
    if (port < 0 || port > 65535) return;
    mockServer.port = port;
    mockServerService.update(mockServer);
    schedulePersist();
    notifyListeners();
  }

  void addMockRoute(MockRoute route) {
    mockServer.routes.insert(0, route);
    mockServerService.update(mockServer);
    schedulePersist();
    notifyListeners();
  }

  void updateMockRoute(MockRoute route) {
    final index = mockServer.routes.indexWhere((item) => item.id == route.id);
    if (index >= 0) {
      mockServer.routes[index] = route;
    } else {
      mockServer.routes.insert(0, route);
    }
    mockServerService.update(mockServer);
    schedulePersist();
    notifyListeners();
  }

  void deleteMockRoute(String id) {
    mockServer.routes.removeWhere((item) => item.id == id);
    mockServerService.update(mockServer);
    schedulePersist();
    notifyListeners();
  }

  void toggleMockRoute(String id, bool enabled) {
    final route = mockServer.routes.where((item) => item.id == id).firstOrNull;
    if (route == null) return;
    route.enabled = enabled;
    mockServerService.update(mockServer);
    schedulePersist();
    notifyListeners();
  }

  /// 从已保存的请求生成 Mock 路由：优先使用第一个响应示例。
  MockRoute mockRouteForEntry(CollectionEntry entry) {
    final request = entry.request;
    final example = entry.examples.isNotEmpty ? entry.examples.first : null;
    final url = request?.url ?? '';
    final path = mockPathFromUrl(url);
    final headers = <KV>[];
    final exampleHeaders = example?.headers ?? const <String, List<String>>{};
    exampleHeaders.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == 'content-length' || lower == 'content-encoding' || lower == 'connection') {
        return;
      }
      headers.add(KV(k: name, v: values.join(', ')));
    });
    return MockRoute(
      name: entry.name,
      method: request?.method.toUpperCase() ?? 'GET',
      path: path,
      status: example?.status ?? 200,
      body: example?.body.isNotEmpty == true ? example!.body : kSampleMockBody,
      headers: headers.isEmpty ? [KV(k: 'content-type', v: 'application/json')] : headers,
      sourceEntryId: entry.id,
    );
  }

  /// 从一条抓包记录生成 Mock 路由。
  MockRoute mockRouteForCapture(CaptureRecord record) => mockRouteFromCapture(record);

  /* -------------------------- 抓包代理 -------------------------- */

  Future<void> startCaptureProxy({
    int port = CaptureProxyService.defaultPort,
    bool mitmHttps = true,
    bool allowInsecureUpstream = true,
  }) async {
    captureCaLoading = true;
    notifyListeners();
    try {
      captureCertificateAuthority ??= await CertificateAuthority.loadOrCreate(storage);
      captureProxyError = await captureProxy.start(
        ca: captureCertificateAuthority!,
        port: port,
        mitmHttps: mitmHttps,
        allowInsecureUpstream: allowInsecureUpstream,
      );
      if (captureProxyError == null) {
        showToast('Traffic capture listening on 127.0.0.1:${captureProxy.port}');
      } else {
        showToast('Capture proxy failed: $captureProxyError');
      }
    } catch (error) {
      captureProxyError = '$error';
      showToast('Capture proxy failed: $error');
    } finally {
      captureCaLoading = false;
      notifyListeners();
    }
  }

  Future<void> stopCaptureProxy() async {
    await captureProxy.stop();
    notifyListeners();
  }

  /// 打开历史抓包请求为新的草稿标签页。
  void openCapturedRequest(CaptureRecord record) {
    if (record.tunneled) {
      showToast('Tunnel-only entries cannot be replayed. Enable HTTPS decryption and trust the CA.');
      return;
    }
    final parsed = Uri.tryParse(record.url);
    final name = parsed == null ? record.url : '${record.method} ${parsed.path.isEmpty ? '/' : parsed.path}';
    openLooseRequest(requestFromCapture(record), name);
    showToast('Captured request opened in a new tab');
  }

  /// 把抓包响应直接存成 Mock 路由。
  void createMockFromCaptureRecord(CaptureRecord record) {
    final route = mockRouteForCapture(record);
    addMockRoute(route);
    showToast('Mock route created from capture');
  }

  /// 把已保存请求（含响应示例）变成 Mock 路由。
  void createMockFromEntry(CollectionEntry entry) {
    addMockRoute(mockRouteForEntry(entry));
    showToast('Mock route created from "${entry.name}"');
  }
}

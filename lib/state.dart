import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/api_service.dart';
import 'services/converters.dart';
import 'services/file_io.dart';
import 'services/oauth.dart';
import 'services/script_service.dart';
import 'services/storage.dart';
import 'services/ws_service.dart';

class AppState extends ChangeNotifier {
  static const String appName = 'Astra';
  static const String version = '2.0.0';

  final Storage storage = Storage();
  final HttpService http = HttpService();
  WsService wsService;
  final ScriptService scripts = ScriptService();

  String mode = 'http';
  ApiRequest _fallbackRequest = ApiRequest();
  WsConfig _fallbackWs = WsConfig();

  /// 右侧编辑器打开的全部标签页（已保存条目 + 未保存草稿）
  List<WorkspaceTab> tabs = [];
  String activeTabId = '';

  /// 当前模式下的全部标签页
  List<WorkspaceTab> tabsFor(String targetMode) =>
      tabs.where((tab) => tab.mode == targetMode).toList();

  WorkspaceTab? get activeTab {
    for (final tab in tabs) {
      if (tab.id == activeTabId && tab.mode == mode) return tab;
    }
    return null;
  }

  ApiRequest get request {
    final tab = activeTab;
    return tab == null ? _fallbackRequest : tab.request;
  }

  set request(ApiRequest value) {
    final tab = activeTab;
    if (tab == null) {
      _fallbackRequest = value;
    } else {
      tab.request = value;
    }
  }

  WsConfig get ws {
    final tab = activeTab;
    return tab == null ? _fallbackWs : tab.ws;
  }

  set ws(WsConfig value) {
    final tab = activeTab;
    if (tab == null) {
      _fallbackWs = value;
    } else {
      tab.ws = value;
    }
  }

  List<Env> environments = [Env()];
  String activeEnvId = '';
  List<CollectionGroup> groups = [];
  List<CollectionFolder> folders = [];

  /// 新建请求时预选的归档位置（集合 / 文件夹），保存时默认使用
  String pendingGroupId = '';
  String pendingFolderId = '';

  List<CollectionEntry> collections = [];
  List<HistoryEntry> history = [];
  List<CookieEntry> cookies = [];

  /// 全局变量：优先级最低，所有请求可见
  List<KV> globals = [];
  AppSettings settings = AppSettings();
  List<MonitorConfig> monitors = [];

  /// 代理 / 客户端证书等全局网络设置
  final OAuthService oauth = OAuthService();

  /// 最近一次响应中被 Set-Cookie 写入的条目
  List<CookieEntry> responseCookies = [];

  /// 最近若干次响应，用于 Diff 对比
  final List<HttpResult> responseHistory = [];

  /// 集合运行器状态
  bool runningCollection = false;
  String runnerProgress = '';
  RunReport? lastReport;
  bool _stopRunner = false;
  final Map<String, Timer> _monitorTimers = {};

  /// SSE 会话
  bool sseRunning = false;
  String? sseStatus;
  final List<SseEvent> sseLog = [];
  SseSession? _sseSession;
  int sseCount = 0;

  /// 变量解析上下文（运行器按条目切换）
  String _ctxGroupId = '';
  String _ctxFolderId = '';
  Map<String, String> _ctxExtra = const {};

  /// 脚本里 pm.execution.setNextRequest 指定的下一个请求
  String? scriptNextRequest;

  AppState({WsService? wsService})
      : wsService = wsService ?? WsService() {
    activeEnvId = environments.first.id;
  }

  Env get env {
    for (final item in environments) {
      if (item.id == activeEnvId) return item;
    }
    return environments.first;
  }

  HttpResult? response;
  String? responseError;
  bool sending = false;
  String? selectedId;
  String? toast;

  /// 脚本执行结果（仅保留最近一次发送）
  bool scriptRan = false;
  List<ScriptLogEntry> scriptLogs = [];
  List<ScriptTestResult> scriptTests = [];
  String? scriptError;

  /// `pm.variables` 写入的本地变量，仅存在于内存中
  Map<String, String> runtimeVars = {};

  String wsState = 'idle'; // idle | connecting | open
  final List<WsMessage> wsLog = [];
  int wsSent = 0;
  int wsReceived = 0;
  String? wsError;

  Timer? _persistTimer;
  Timer? _draftTimer;
  Timer? _toastTimer;

  /* ------------------------------------------------------------------ */
  /* 变量                                                                */
  /* ------------------------------------------------------------------ */

  String _ctxEntryId = '';

  String get _activeGroupId =>
      _ctxGroupId.isNotEmpty ? _ctxGroupId : (activeTab?.groupId ?? pendingGroupId);

  String get _activeFolderId =>
      _ctxFolderId.isNotEmpty ? _ctxFolderId : (activeTab?.folderId ?? pendingFolderId);

  /// 按 Postman 的优先级合并变量：
  /// 全局 < 集合 < 外层文件夹 < 内层文件夹 < 环境 < 当前请求 < 运行时 / 数据文件。
  Map<String, String> get varMap =>
      _varMap(_activeGroupId, _activeFolderId, _ctxExtra);

  Map<String, String> _varMap(
    String groupId,
    String folderId,
    Map<String, String> extra,
  ) {
    final map = <String, String>{};
    void putAll(Iterable<KV> list) {
      for (final item in list) {
        final key = item.k.trim();
        if (key.isNotEmpty) map[key] = item.v;
      }
    }

    putAll(globals);
    final group = groups.where((item) => item.id == groupId).firstOrNull;
    if (group != null) putAll(group.variables);

    final chain = <CollectionFolder>[];
    var current = folders.where((item) => item.id == folderId).firstOrNull;
    var guard = 0;
    while (current != null && guard < 32) {
      chain.insert(0, current);
      final parentId = current.parentId;
      current = parentId.isEmpty
          ? null
          : folders.where((item) => item.id == parentId).firstOrNull;
      guard += 1;
    }
    for (final folder in chain) {
      putAll(folder.variables);
    }

    putAll(env.vars);
    final entryId = _ctxEntryId.isNotEmpty ? _ctxEntryId : selectedId;
    final entry = collections.where((item) => item.id == entryId).firstOrNull;
    if (entry != null) putAll(entry.variables);
    map.addAll(runtimeVars);
    map.addAll(extra);
    return map;
  }

  /// 变量面板使用的完整来源列表（低 → 高优先级）。
  List<VariableScope> variableScopes() {
    final scopes = <VariableScope>[
      VariableScope('全局', globals),
    ];
    for (final group in groups) {
      scopes.add(VariableScope('集合 · ${group.name}', group.variables));
    }
    for (final folder in folders) {
      final path = folderPath(folder.id);
      scopes.add(VariableScope('文件夹 · $path', folder.variables));
    }
    scopes.add(VariableScope('环境 · ${env.name}', env.vars));
    return scopes;
  }

  String resolve(String input) {
    if (input.isEmpty) return input;
    final map = varMap;
    return input.replaceAllMapped(RegExp(r'\{\{\s*([\w.-]+)\s*\}\}'), (match) {
      final key = match.group(1)!;
      return map.containsKey(key) ? map[key]! : match.group(0)!;
    });
  }

  /// 是否还存在未解析的变量占位符。
  bool hasUnresolved(String input) =>
      RegExp(r'\{\{\s*[\w.-]+\s*\}\}').hasMatch(input);

  /* ------------------------------------------------------------------ */
  /* 认证继承                                                            */
  /* ------------------------------------------------------------------ */

  /// 解析请求最终使用的认证配置：请求 → 文件夹 → 集合。
  AuthConfig effectiveAuth([ApiRequest? req]) {
    final source = _source(req);
    if (source.auth.type != 'inherit') return source.auth;
    final folderId = _activeFolderId;
    var folder = folders.where((item) => item.id == folderId).firstOrNull;
    var guard = 0;
    while (folder != null && guard < 32) {
      if (folder.auth.type != 'inherit') return folder.auth;
      final parentId = folder.parentId;
      folder = parentId.isEmpty
          ? null
          : folders.where((item) => item.id == parentId).firstOrNull;
      guard += 1;
    }
    final groupId = _activeGroupId;
    final group = groups.where((item) => item.id == groupId).firstOrNull;
    if (group != null && group.auth.type != 'inherit') return group.auth;
    return AuthConfig(type: 'none');
  }

  /// 认证继承来源描述，供 UI 提示。
  String authSourceLabel(ApiRequest req) {
    if (req.auth.type != 'inherit') return '当前请求';
    var folder = folders.where((item) => item.id == _activeFolderId).firstOrNull;
    var guard = 0;
    while (folder != null && guard < 32) {
      final current = folder;
      if (current.auth.type != 'inherit') return '文件夹 · ${current.name}';
      folder = current.parentId.isEmpty
          ? null
          : folders.where((item) => item.id == current.parentId).firstOrNull;
      guard += 1;
    }
    final group = groups.where((item) => item.id == _activeGroupId).firstOrNull;
    if (group != null && group.auth.type != 'inherit') return '集合 · ${group.name}';
    return '无';
  }


  /* ------------------------------------------------------------------ */
  /* 请求构建                                                            */
  /* ------------------------------------------------------------------ */

  ApiRequest _source(ApiRequest? req) => req ?? request;

  Map<String, String> collectHeaders([ApiRequest? req]) {
    final source = _source(req);
    final headers = <String, String>{};
    for (final item in source.headers) {
      if (item.on && item.k.trim().isNotEmpty) {
        headers[item.k.trim()] = resolve(item.v);
      }
    }
    final auth = effectiveAuth(source);
    if (auth.type == 'bearer' && auth.token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${resolve(auth.token).trim()}';
    } else if (auth.type == 'basic') {
      final raw = '${resolve(auth.username)}:${resolve(auth.password)}';
      headers['Authorization'] = 'Basic ${base64Utf8(raw)}';
    } else if (auth.type == 'oauth2' && auth.token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${resolve(auth.token).trim()}';
    } else if (auth.type == 'apikey' &&
        auth.apiKeyIn == 'header' &&
        auth.apiKeyName.trim().isNotEmpty) {
      headers[auth.apiKeyName.trim()] = resolve(auth.apiKeyValue);
    }
    return headers;
  }

  String buildUrl([ApiRequest? req]) {
    final source = _source(req);
    var raw = resolve(source.url).trim();
    if (raw.isEmpty) throw HttpFailure('请输入请求地址');
    if (!RegExp(r'^[a-zA-Z][\w+.-]*://').hasMatch(raw)) {
      raw = 'http://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) throw HttpFailure('请求地址格式无效');

    final params = source.params
        .where((item) => item.on && item.k.trim().isNotEmpty)
        .map((item) =>
            '${Uri.encodeQueryComponent(resolve(item.k))}=${Uri.encodeQueryComponent(resolve(item.v))}')
        .toList();
    final auth = effectiveAuth(source);
    if (auth.type == 'apikey' &&
        auth.apiKeyIn == 'query' &&
        auth.apiKeyName.trim().isNotEmpty) {
      params.add(
        '${Uri.encodeQueryComponent(auth.apiKeyName.trim())}='
        '${Uri.encodeQueryComponent(resolve(auth.apiKeyValue))}',
      );
    }
    if (params.isEmpty) return raw;
    final base = raw.split('#').first;
    final joiner = base.contains('?')
        ? (base.endsWith('?') || base.endsWith('&') ? '' : '&')
        : '?';
    return '$base$joiner${params.join('&')}';
  }

  String buildBody([ApiRequest? req]) {
    final source = _source(req);
    switch (source.bodyMode) {
      case 'json':
      case 'text':
        return resolve(source.body);
      case 'form':
        return source.form
            .where((item) => item.on && item.k.trim().isNotEmpty)
            .map((item) =>
                '${Uri.encodeQueryComponent(resolve(item.k))}=${Uri.encodeQueryComponent(resolve(item.v))}')
            .join('&');
      case 'graphql':
        final query = resolve(source.graphqlQuery);
        final rawVars = resolve(source.graphqlVars).trim();
        Object variables = const <String, dynamic>{};
        if (rawVars.isNotEmpty) {
          try {
            variables = jsonDecode(rawVars);
          } catch (_) {
            throw HttpFailure('GraphQL Variables 不是合法 JSON');
          }
        }
        return jsonEncode({'query': query, 'variables': variables});
    }
    return '';
  }

  /// 把 gRPC-Web 载荷编码成带 5 字节前缀的帧。
  Uint8List buildGrpcFrame(ApiRequest source) {
    final payload = resolve(source.grpcPayload).trim();
    if (payload.isEmpty) return encodeGrpcFrame(const []);
    if (!source.grpcBinary) return encodeGrpcFrame(utf8.encode(payload));
    try {
      return encodeGrpcFrame(base64Decode(payload.replaceAll(RegExp(r'\s+'), '')));
    } catch (_) {
      throw HttpFailure('gRPC 载荷不是合法 base64');
    }
  }

  List<FormRow> buildMultipart([ApiRequest? req]) {
    final source = _source(req);
    return source.formData
        .where((row) => row.on && row.k.trim().isNotEmpty)
        .map((row) => FormRow(
              on: true,
              k: resolve(row.k).trim(),
              v: row.type == 'file' ? '' : resolve(row.v),
              type: row.type,
              file: row.file,
            ))
        .toList();
  }

  bool _hasHeader(Map<String, String> headers, String name) =>
      headers.keys.any((key) => key.toLowerCase() == name.toLowerCase());

  /* ------------------------------------------------------------------ */
  /* 发送请求                                                            */
  /* ------------------------------------------------------------------ */

  Future<void> send() async {
    if (sending) return;
    if (request.options.streamSse) {
      await startSse();
      return;
    }
    sending = true;
    responseError = null;
    responseCookies = [];
    scriptRan = false;
    scriptLogs = [];
    scriptTests = [];
    scriptError = null;
    scriptNextRequest = null;
    notifyListeners();

    final snapshot = request.copy();
    final work = request.copy();
    String url = '';
    try {
      await _refreshOAuthIfNeeded(work);
      _runScript(work.preScript, work, event: 'prerequest');
      final effective = work;

      url = buildUrl(effective);
      final headers = collectHeaders(effective);
      final body = buildBody(effective);
      final multipart =
          effective.bodyMode == 'form-data' ? buildMultipart(effective) : <FormRow>[];

      if (effective.bodyMode == 'json' && !_hasHeader(headers, 'content-type')) {
        headers['Content-Type'] = 'application/json';
      } else if (effective.bodyMode == 'text' && !_hasHeader(headers, 'content-type')) {
        headers['Content-Type'] = 'text/plain; charset=utf-8';
      } else if (effective.bodyMode == 'form' && !_hasHeader(headers, 'content-type')) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
      } else if (effective.bodyMode == 'graphql' &&
          !_hasHeader(headers, 'content-type')) {
        headers['Content-Type'] = 'application/json';
      } else if (effective.bodyMode == 'grpc') {
        if (!_hasHeader(headers, 'content-type')) {
          headers['Content-Type'] =
              'application/grpc-web+${effective.grpcBinary ? 'proto' : 'json'}';
        }
        headers['x-grpc-web'] = '1';
        headers['accept'] = 'application/grpc-web+proto';
      }

      final manage = effective.options.manageCookies;
      final limit = effective.options.timeoutSeconds;
      final result = await http.send(
        method: effective.method,
        url: url,
        headers: headers,
        body: body,
        multipart: multipart,
        followRedirects: effective.options.followRedirects,
        rejectUnauthorized: effective.options.rejectUnauthorized,
        cookies: manage ? cookies : <CookieEntry>[],
        onCookies: (incoming) => responseCookies = incoming,
        timeout: limit <= 0 ? const Duration(days: 365) : Duration(seconds: limit),
        settings: settings,
        rawBody:
            effective.bodyMode == 'grpc' ? buildGrpcFrame(effective) : null,
      );
      response = result;
      responseError = null;
      responseHistory.insert(0, result);
      if (responseHistory.length > 6) responseHistory.removeLast();
      _runScript(work.postScript, work, event: 'test', response: result);
      _pushHistory(snapshot, url, result.status, result.ms);
    } catch (err) {
      response = null;
      responseError = err is HttpFailure ? err.message : '$err';
      _pushHistory(snapshot, url, null, 0);
    } finally {
      sending = false;
      notifyListeners();
      _schedulePersist();
    }
  }

  /// OAuth2 token 过期时尝试用 refresh_token 自动续期。
  Future<void> _refreshOAuthIfNeeded(ApiRequest work) async {
    final auth = effectiveAuth(work);
    if (auth.type != 'oauth2' || !auth.oauthExpired) return;
    if (auth.oauthRefreshToken.trim().isEmpty) return;
    final result = await oauth.refresh(
      tokenUrl: resolve(auth.oauthTokenUrl),
      refreshToken: auth.oauthRefreshToken,
      clientId: resolve(auth.oauthClientId),
      clientSecret: resolve(auth.oauthClientSecret),
    );
    if (result.token != null && result.token!.isNotEmpty) {
      auth.token = result.token!;
      auth.oauthExpiresAt = result.expiresAt;
      if ((result.refreshToken ?? '').isNotEmpty) {
        auth.oauthRefreshToken = result.refreshToken!;
      }
    }
  }

  /* ------------------------------------------------------------------ */
  /* SSE 事件流                                                          */
  /* ------------------------------------------------------------------ */

  Future<void> startSse() async {
    if (sseRunning) return;
    await stopSse();
    sseRunning = true;
    sseStatus = '正在连接…';
    sseLog.clear();
    sseCount = 0;
    notifyListeners();

    final work = request.copy();
    String url = '';
    try {
      await _refreshOAuthIfNeeded(work);
      _runScript(work.preScript, work, event: 'prerequest');
      url = buildUrl(work);
      final headers = collectHeaders(work);
      final session = await http.openEventStream(
        url: url,
        headers: headers,
        rejectUnauthorized: work.options.rejectUnauthorized,
        timeout: const Duration(seconds: 30),
        settings: settings,
      );
      if (!sseRunning) {
        await session.close();
        return;
      }
      _sseSession = session;
      sseStatus = '已连接（HTTP ${session.status}），等待事件…';
      _pushHistory(request.copy(), url, session.status, 0);
      session.events.listen(
        (event) {
          sseLog.add(event);
          sseCount += 1;
          if (sseLog.length > 600) sseLog.removeAt(0);
          notifyListeners();
        },
        onError: (Object err) {
          sseStatus = '连接错误：$err';
          sseRunning = false;
          _sseSession = null;
          notifyListeners();
        },
        onDone: () {
          sseStatus = '连接已结束';
          sseRunning = false;
          _sseSession = null;
          notifyListeners();
          _schedulePersist();
        },
      );
    } catch (err) {
      sseRunning = false;
      sseStatus = err is HttpFailure ? err.message : '$err';
    }
    notifyListeners();
  }

  Future<void> stopSse() async {
    final session = _sseSession;
    _sseSession = null;
    if (session != null) {
      await session.close();
    }
    if (sseRunning) {
      sseRunning = false;
      sseStatus ??= '已停止';
      notifyListeners();
    }
  }

  /// 执行前置 / 后置脚本，并把结果应用到本次请求副本与环境变量。
  void _runScript(
    String source,
    ApiRequest target, {
    required String event,
    HttpResult? response,
  }) {
    if (source.trim().isEmpty) return;
    scriptRan = true;
    final outcome = scripts.run(
      source: source,
      input: ScriptInput(
        method: target.method,
        url: target.url,
        bodyMode: target.bodyMode,
        body: target.bodyMode == 'json' || target.bodyMode == 'text'
            ? target.body
            : buildBody(target),
        headers: _scriptHeaders(target),
        env: varMap,
        vars: Map.of(runtimeVars),
        globals: _mapOf(globals),
        collection: _collectionVars(_activeGroupId),
        requestName: _nameFromUrl(target.url),
        event: event,
      ),
      response: response,
    );
    if (outcome == null) return;

    scriptLogs = [...scriptLogs, ...outcome.logs];
    scriptTests = [...scriptTests, ...outcome.tests];
    if (outcome.nextRequest != null && outcome.nextRequest!.isNotEmpty) {
      scriptNextRequest = outcome.nextRequest;
    }
    if (outcome.error != null && outcome.error!.isNotEmpty) {
      scriptError = outcome.error;
    }

    // 引擎不可用时不会返回请求地址，此时保持原请求与变量不变
    if (outcome.url.isEmpty && outcome.error != null) return;

    // 环境变量与本地变量：脚本结果即为最新全量状态
    final list = outcome.env.entries.map((entry) => KV(k: entry.key, v: entry.value)).toList();
    env.vars = list.isEmpty ? [KV()] : list;
    runtimeVars = Map.of(outcome.vars);
    if (outcome.globals.isNotEmpty || globals.isNotEmpty) {
      globals = outcome.globals.entries
          .map((entry) => KV(k: entry.key, v: entry.value))
          .toList();
    }

    // 请求改写只在前置脚本中生效
    if (event != 'prerequest') return;
    if (outcome.method.trim().isNotEmpty) target.method = outcome.method.trim().toUpperCase();
    if (outcome.url.trim().isNotEmpty) target.url = outcome.url;
    target.bodyMode = _normalizeBodyMode(outcome.bodyMode, outcome.body);
    if (target.bodyMode == 'json' || target.bodyMode == 'text') {
      target.body = outcome.body;
    }
    target.headers = outcome.headers.isEmpty
        ? [KV()]
        : outcome.headers
            .map((header) => KV(on: !header.disabled, k: header.key, v: header.value))
            .toList();
  }

  Map<String, String> _scriptHeaders(ApiRequest req) {
    final headers = <String, String>{};
    for (final item in req.headers) {
      if (item.on && item.k.trim().isNotEmpty) {
        headers[item.k.trim()] = item.v;
      }
    }
    return headers;
  }

  Map<String, String> _mapOf(List<KV> list) {
    final map = <String, String>{};
    for (final item in list) {
      final key = item.k.trim();
      if (key.isNotEmpty) map[key] = item.v;
    }
    return map;
  }

  Map<String, String> _collectionVars(String groupId) {
    final group = groups.where((item) => item.id == groupId).firstOrNull;
    return group == null ? const {} : _mapOf(group.variables);
  }

  String _normalizeBodyMode(String mode, String body) {
    switch (mode) {
      case 'json':
      case 'text':
      case 'form':
      case 'form-data':
      case 'graphql':
      case 'grpc':
      case 'none':
        return mode;
      case 'raw':
        final trimmed = body.trimLeft();
        return trimmed.startsWith('{') || trimmed.startsWith('[') ? 'json' : 'text';
    }
    return mode.isEmpty ? 'none' : mode;
  }

  /// 使用 OAuth 2.0 配置获取 access_token，成功后写回请求配置。
  /// 支持 client_credentials / password / authorization_code（含 PKCE）。
  Future<String?> fetchOAuthToken(ApiRequest target, {bool force = false}) async {
    final auth = target.auth;
    if (auth.type != 'oauth2') return '请先把认证类型切换为 OAuth 2.0';
    if (!force && auth.token.trim().isNotEmpty && !auth.oauthExpired) {
      return null;
    }
    if (auth.oauthGrantType == 'authorization_code') {
      final result = await oauth.authorizationCode(
        authUrl: resolve(auth.oauthAuthUrl),
        tokenUrl: resolve(auth.oauthTokenUrl),
        clientId: resolve(auth.oauthClientId),
        clientSecret: resolve(auth.oauthClientSecret),
        scope: resolve(auth.oauthScope),
        pkce: auth.oauthPkce,
      );
      return _applyOAuth(auth, result);
    }
    final tokenUrl = resolve(auth.oauthTokenUrl).trim();
    if (tokenUrl.isEmpty) return '请先填写 Token 端点地址';
    final result = await oauth.clientCredentials(
      tokenUrl: tokenUrl,
      clientId: resolve(auth.oauthClientId),
      clientSecret: resolve(auth.oauthClientSecret),
      scope: resolve(auth.oauthScope),
      username: auth.oauthGrantType == 'password' ? resolve(auth.username) : null,
      password: auth.oauthGrantType == 'password' ? resolve(auth.password) : null,
    );
    return _applyOAuth(auth, result);
  }

  String? _applyOAuth(AuthConfig auth, OAuthTokenResult result) {
    if (result.token == null || result.token!.isEmpty) {
      return result.error ?? '获取 Token 失败';
    }
    auth
      ..token = result.token!
      ..oauthExpiresAt = result.expiresAt;
    if ((result.refreshToken ?? '').isNotEmpty) {
      auth.oauthRefreshToken = result.refreshToken!;
    }
    notifyListeners();
    _scheduleDraft();
    _schedulePersist();
    return null;
  }


  /// 把请求转换为 cURL 命令（含变量替换后的地址、认证头、Body）。
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
    if (text.isEmpty) throw const FormatException('请输入 cURL 命令');
    // 去掉复制时常见的行首提示符与换行续行
    text = text.replaceAll(RegExp(r'\\\r?\n'), ' ').replaceAll(RegExp(r'\r?\n'), ' ');
    final tokens = _tokenizeShell(text);
    if (tokens.isEmpty || !tokens.first.toLowerCase().contains('curl')) {
      throw const FormatException('内容不是有效的 cURL 命令');
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

    if (url == null || url.trim().isEmpty) throw const FormatException('未找到请求地址');
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

  void _pushHistory(ApiRequest snapshot, String url, int? status, int ms) {
    history.insert(
      0,
      HistoryEntry(
        mode: 'http',
        name: _nameFromUrl(url),
        method: snapshot.method,
        url: url,
        status: status,
        ms: ms,
        snapshot: snapshot,
      ),
    );
    if (history.length > 80) history = history.sublist(0, 80);
  }

  String _nameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.isNotEmpty) return last;
    }
    return url.isEmpty ? '未命名请求' : url;
  }

  /* ------------------------------------------------------------------ */
  /* WebSocket                                                           */
  /* ------------------------------------------------------------------ */

  Future<void> connectWs() async {
    if (wsState != 'idle') return;
    var url = resolve(ws.url).trim();
    if (url.isEmpty) {
      _wsSystem('请输入 WebSocket 地址');
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
    _wsSystem('正在连接 $url');
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
          _wsSystem('连接已建立');
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
              '[二进制 ${data.length} 字节] ${utf8.decode(data, allowMalformed: true)}',
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
          _wsSystem('错误：$message');
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
    _wsSystem('已断开连接');
    notifyListeners();
  }

  void sendWs(String text) {
    if (wsState != 'open') {
      _wsSystem('尚未建立连接');
      return;
    }
    try {
      wsService.send(text);
      wsSent += 1;
      wsLog.add(WsMessage(text, outgoing: true));
      notifyListeners();
    } catch (err) {
      _wsSystem('发送失败：$err');
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

  /* ------------------------------------------------------------------ */
  /* 集合 / 历史                                                          */
  /* ------------------------------------------------------------------ */

  /// 当前标签页名称（没有标签页时为空）
  String get activeName => activeTab?.name ?? '';

  /// 直接修改当前 API / 连接名称
  void renameActive(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final tab = activeTab;
    if (tab != null) {
      tab.name = trimmed;
    } else {
      final created = WorkspaceTab(
        name: trimmed,
        mode: mode,
        groupId: pendingGroupId,
        folderId: pendingFolderId,
        request: _fallbackRequest.copy(),
        ws: _fallbackWs.copy(),
      );
      tabs.add(created);
      activeTabId = created.id;
    }
    notifyListeners();
    _scheduleDraft();
  }

  /// Ctrl / ⌘ + S：按当前名称与归档位置直接保存，不弹窗。
  void saveActive() {
    final tab = activeTab;
    final current = (tab?.name ?? '').trim();
    final url = mode == 'ws' ? ws.url : request.url;
    final name = current.isEmpty || current == _draftName(mode)
        ? _nameFromUrl(url)
        : current;
    saveCurrent(name);
    showToast('已保存');
  }

  void switchMode(String next) {
    if (mode == next) return;
    mode = next;
    final sameMode = tabs.where((tab) => tab.mode == next).toList();
    if (sameMode.isNotEmpty) {
      _activateTab(sameMode.last);
    } else {
      activeTabId = '';
      selectedId = null;
      pendingGroupId = '';
      pendingFolderId = '';
      if (next == 'ws') {
        _fallbackWs = WsConfig();
      } else {
        _fallbackRequest = ApiRequest();
      }
      response = null;
      responseError = null;
      _clearScriptResult();
    }
    notifyListeners();
    _scheduleDraft();
  }

  String _draftName(String targetMode) =>
      targetMode == 'ws' ? '未命名连接' : '未命名 API';

  WorkspaceTab _createTab({
    required String name,
    required String targetMode,
    String groupId = '',
    String folderId = '',
    String entryId = '',
    String historyId = '',
    ApiRequest? request,
    WsConfig? ws,
  }) {
    final tab = WorkspaceTab(
      name: name,
      mode: targetMode,
      groupId: groupId,
      folderId: folderId,
      entryId: entryId,
      historyId: historyId,
      request: request,
      ws: ws,
    );
    tabs.add(tab);
    _activateTab(tab);
    return tab;
  }

  /// 切换到指定标签页，并同步模式与归档位置。
  void _activateTab(WorkspaceTab tab) {
    activeTabId = tab.id;
    mode = tab.mode;
    selectedId = tab.entryId.isEmpty ? null : tab.entryId;
    pendingGroupId = tab.groupId;
    pendingFolderId = tab.folderId;
    response = null;
    responseError = null;
    _clearScriptResult();
  }

  void activateTab(String id) {
    final tab = tabs.where((item) => item.id == id).firstOrNull;
    if (tab == null || tab.id == activeTabId) return;
    _activateTab(tab);
    notifyListeners();
    _scheduleDraft();
  }

  void closeTab(String id) {
    final index = tabs.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final wasActive = activeTabId == id;
    tabs.removeAt(index);
    if (wasActive) {
      if (tabs.isEmpty) {
        activeTabId = '';
        selectedId = null;
        pendingGroupId = '';
        pendingFolderId = '';
        if (mode == 'ws') {
          _fallbackWs = WsConfig();
        } else {
          _fallbackRequest = ApiRequest();
        }
        response = null;
        responseError = null;
        _clearScriptResult();
      } else {
        _activateTab(tabs[(index - 1).clamp(0, tabs.length - 1)]);
      }
    }
    notifyListeners();
    _scheduleDraft();
  }

  void newRequest() {
    _createTab(name: _draftName(mode), targetMode: mode);
    response = null;
    responseError = null;
    _clearScriptResult();
    notifyListeners();
    _scheduleDraft();
  }

  /// 在指定集合 / 文件夹下新建请求，保存时会默认归档到该位置。
  void newRequestIn(String groupId, String folderId) {
    final group = groups.where((item) => item.id == groupId).firstOrNull;
    final targetMode = group?.mode ?? mode;
    if (group != null) group.expanded = true;
    _expandFolderChain(folderId);
    _createTab(
      name: _draftName(targetMode),
      targetMode: targetMode,
      groupId: groupId,
      folderId: folderId,
    );
    response = null;
    responseError = null;
    _clearScriptResult();
    notifyListeners();
    _scheduleDraft();
    showToast('已在该位置新建${targetMode == 'ws' ? '连接' : ' API 请求'}，填写后按 ⌘ / Ctrl + S 保存');
  }

  /// 解析 cURL 并在当前 Session 新建一个请求标签页。
  void openCurl(String source) {
    final parsed = parseCurl(source);
    if (mode != 'http') switchMode('http');
    _createTab(
      name: _nameFromUrl(parsed.url),
      targetMode: 'http',
      request: parsed,
    );
    pendingGroupId = '';
    pendingFolderId = '';
    notifyListeners();
    _scheduleDraft();
    showToast('已从 cURL 创建请求');
  }

  void openEntry(CollectionEntry entry) {
    final opened = tabs.where((tab) => tab.entryId == entry.id).firstOrNull;
    if (opened != null) {
      _activateTab(opened);
    } else {
      _createTab(
        name: entry.name,
        targetMode: entry.mode,
        groupId: entry.groupId,
        folderId: entry.folderId,
        entryId: entry.id,
        request: entry.request?.copy(),
        ws: entry.ws?.copy(),
      );
    }
    notifyListeners();
    _scheduleDraft();
  }

  void openHistory(HistoryEntry entry) {
    // 同一条历史记录已经打开过，则直接切到已有标签页，避免重复创建
    final existing = tabs.firstWhere(
      (tab) => tab.historyId == entry.id,
      orElse: () => WorkspaceTab(id: ''),
    );
    if (existing.id.isNotEmpty) {
      _activateTab(existing);
      notifyListeners();
      _scheduleDraft();
      return;
    }
    if (entry.mode == 'ws') {
      _createTab(
        name: entry.name.isEmpty ? _draftName('ws') : entry.name,
        targetMode: 'ws',
        historyId: entry.id,
        ws: entry.wsSnapshot?.copy() ?? WsConfig(url: entry.url),
      );
    } else {
      _createTab(
        name: entry.name.isEmpty ? _draftName('http') : entry.name,
        targetMode: 'http',
        historyId: entry.id,
        request: entry.snapshot?.copy() ?? ApiRequest(method: entry.method, url: entry.url),
      );
    }
    notifyListeners();
    _scheduleDraft();
  }

  void _clearScriptResult() {
    scriptRan = false;
    scriptLogs = [];
    scriptTests = [];
    scriptError = null;
  }

  void saveCurrent(String name, {String? groupId, String? folderId}) {
    final existing = collections.where((item) => item.id == selectedId).firstOrNull;
    final targetGroup = groupId ?? existing?.groupId ?? pendingGroupId;
    var targetFolder = folderId ?? existing?.folderId ?? pendingFolderId;
    if (!folders.any((item) => item.id == targetFolder && item.groupId == targetGroup)) {
      targetFolder = '';
    }
    final entry = CollectionEntry(
      id: selectedId,
      name: name.trim().isEmpty ? '未命名请求' : name.trim(),
      mode: mode,
      groupId: targetGroup,
      folderId: targetFolder,
      request: mode == 'http' ? request.copy() : null,
      ws: mode == 'ws' ? ws.copy() : null,
    );
    final index = collections.indexWhere((item) => item.id == entry.id);
    if (index >= 0) {
      collections[index] = entry;
    } else {
      collections.insert(0, entry);
    }
    final tab = activeTab;
    if (tab != null) {
      tab
        ..entryId = entry.id
        ..historyId = ''
        ..name = entry.name
        ..mode = mode
        ..groupId = targetGroup
        ..folderId = targetFolder;
    } else {
      final created = WorkspaceTab(
        name: entry.name,
        mode: mode,
        groupId: targetGroup,
        folderId: targetFolder,
        entryId: entry.id,
        request: mode == 'http' ? request.copy() : null,
        ws: mode == 'ws' ? ws.copy() : null,
      );
      tabs.add(created);
      activeTabId = created.id;
    }
    selectedId = entry.id;
    pendingGroupId = targetGroup;
    pendingFolderId = targetFolder;
    notifyListeners();
    _schedulePersist();
    _scheduleDraft();
  }

  void deleteEntry(String id) {
    collections.removeWhere((item) => item.id == id);
    for (final tab in tabs) {
      if (tab.entryId == id) tab.entryId = '';
    }
    if (selectedId == id) selectedId = null;
    notifyListeners();
    _schedulePersist();
  }

  List<HistoryEntry> historyFor(String targetMode) =>
      history.where((item) => item.mode == targetMode).toList();

  void deleteHistoryEntry(String id) {
    history.removeWhere((item) => item.id == id);
    notifyListeners();
    _schedulePersist();
  }

  void deleteHistoryEntries(Set<String> ids) {
    history.removeWhere((item) => ids.contains(item.id));
    notifyListeners();
    _schedulePersist();
  }

  void clearHistory() {
    history.clear();
    notifyListeners();
    _schedulePersist();
  }

  /* ------------------------------------------------------------------ */
  /* 集合分组                                                            */
  /* ------------------------------------------------------------------ */

  List<CollectionGroup> groupsFor(String targetMode) =>
      groups.where((group) => group.mode == targetMode).toList();

  List<CollectionEntry> entriesFor(String targetMode) =>
      collections.where((entry) => entry.mode == targetMode).toList();

  CollectionGroup createGroup(String name, String targetMode) {
    final group = CollectionGroup(
      name: name.trim().isEmpty ? '新建集合' : name.trim(),
      mode: targetMode,
    );
    groups.add(group);
    notifyListeners();
    _schedulePersist();
    return group;
  }

  void renameGroup(String id, String name) {
    final group = groups.where((item) => item.id == id).firstOrNull;
    if (group == null) return;
    group.name = name.trim().isEmpty ? group.name : name.trim();
    notifyListeners();
    _schedulePersist();
  }

  void deleteGroup(String id) {
    // 收集该集合下所有文件夹
    final folderIds = <String>{};
    for (final folder in folders) {
      if (folder.groupId == id) folderIds.add(folder.id);
    }
    // 删除该集合下的全部请求 / 连接
    final deletedEntryIds = <String>{};
    collections.removeWhere((entry) {
      if (entry.groupId == id) {
        deletedEntryIds.add(entry.id);
        return true;
      }
      return false;
    });
    // 集合被删，打开的对应标签页变为未分组草稿
    for (final tab in tabs) {
      if (tab.groupId == id) {
        if (deletedEntryIds.contains(tab.entryId)) tab.entryId = '';
        tab.groupId = '';
        tab.folderId = '';
      } else if (deletedEntryIds.contains(tab.entryId)) {
        tab.entryId = '';
      }
    }
    folders.removeWhere((item) => folderIds.contains(item.id));
    groups.removeWhere((item) => item.id == id);
    if (pendingGroupId == id) {
      pendingGroupId = '';
      pendingFolderId = '';
    } else if (folderIds.contains(pendingFolderId)) {
      pendingFolderId = '';
    }
    notifyListeners();
    _schedulePersist();
    _scheduleDraft();
  }

  /* ------------------------------------------------------------------ */
  /* 集合内文件夹                                                        */
  /* ------------------------------------------------------------------ */

  List<CollectionFolder> rootFolders(String groupId) =>
      folders.where((item) => item.groupId == groupId && item.parentId.isEmpty).toList();

  List<CollectionFolder> childFolders(String parentId) =>
      folders.where((item) => item.parentId == parentId).toList();

  List<CollectionEntry> entriesInFolder(String folderId) =>
      collections.where((item) => item.folderId == folderId).toList();

  List<CollectionEntry> entriesInGroupRoot(String groupId) => collections
      .where((item) => item.groupId == groupId && item.folderId.isEmpty)
      .toList();

  /// 展开目标文件夹及其所有上级，保证新建的请求在侧栏中可见。
  void _expandFolderChain(String folderId) {
    var current = folders.where((item) => item.id == folderId).firstOrNull;
    var guard = 0;
    while (current != null && guard < 32) {
      current.expanded = true;
      final parentId = current.parentId;
      current = parentId.isEmpty
          ? null
          : folders.where((item) => item.id == parentId).firstOrNull;
      guard += 1;
    }
  }

  CollectionFolder createFolder(String groupId, String parentId, String name) {
    final folder = CollectionFolder(
      groupId: groupId,
      parentId: parentId,
      name: name.trim().isEmpty ? '新建文件夹' : name.trim(),
    );
    folders.add(folder);
    if (parentId.isNotEmpty) {
      final parent = folders.where((item) => item.id == parentId).firstOrNull;
      parent?.expanded = true;
    }
    notifyListeners();
    _schedulePersist();
    return folder;
  }

  void renameFolder(String id, String name) {
    final folder = folders.where((item) => item.id == id).firstOrNull;
    if (folder == null) return;
    folder.name = name.trim().isEmpty ? folder.name : name.trim();
    notifyListeners();
    _schedulePersist();
  }

  void toggleFolder(String id) {
    final folder = folders.where((item) => item.id == id).firstOrNull;
    if (folder == null) return;
    folder.expanded = !folder.expanded;
    notifyListeners();
    _schedulePersist();
  }

  void deleteFolder(String id) {
    final target = folders.where((item) => item.id == id).firstOrNull;
    if (target == null) return;
    // 递归收集所有后代文件夹 id
    final ids = <String>{id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final folder in folders) {
        if (ids.contains(folder.parentId) && !ids.contains(folder.id)) {
          ids.add(folder.id);
          changed = true;
        }
      }
    }
    // 删除这些文件夹内的全部请求 / 连接
    final deletedEntryIds = <String>{};
    collections.removeWhere((entry) {
      if (ids.contains(entry.folderId)) {
        deletedEntryIds.add(entry.id);
        return true;
      }
      return false;
    });
    // 命中的标签页：条目已删，变为草稿并上移到被删文件夹的上一级
    for (final tab in tabs) {
      if (ids.contains(tab.folderId)) {
        if (deletedEntryIds.contains(tab.entryId)) tab.entryId = '';
        tab.folderId = target.parentId;
      } else if (deletedEntryIds.contains(tab.entryId)) {
        tab.entryId = '';
      }
    }
    if (ids.contains(pendingFolderId)) pendingFolderId = target.parentId;
    folders.removeWhere((item) => ids.contains(item.id));
    notifyListeners();
    _schedulePersist();
    _scheduleDraft();
  }

  /// 浮层展示的文件夹路径，例如「用户服务 / 管理端 / 详情」
  String folderPath(String folderId) {
    final parts = <String>[];
    var current = folders.where((item) => item.id == folderId).firstOrNull;
    var guard = 0;
    while (current != null && guard < 32) {
      parts.insert(0, current.name);
      final parentId = current.parentId;
      current = parentId.isEmpty
          ? null
          : folders.where((item) => item.id == parentId).firstOrNull;
      guard += 1;
    }
    return parts.join(' / ');
  }

  void toggleGroup(String id) {
    final group = groups.where((item) => item.id == id).firstOrNull;
    if (group == null) return;
    group.expanded = !group.expanded;
    notifyListeners();
    _schedulePersist();
  }

  void moveEntryToGroup(String entryId, String groupId) =>
      moveEntry(entryId, groupId, '');

  /// 把请求 / 连接移动到指定集合与文件夹，并展开目标位置。
  void moveEntry(String entryId, String groupId, String folderId) {
    final entry = collections.where((item) => item.id == entryId).firstOrNull;
    if (entry == null) return;
    final group = groups.where((item) => item.id == groupId).firstOrNull;
    if (group == null || group.mode != entry.mode) return;
    entry
      ..groupId = groupId
      ..folderId = folders.any((f) => f.id == folderId && f.groupId == groupId)
          ? folderId
          : '';
    group.expanded = true;
    _expandFolderChain(entry.folderId);
    for (final tab in tabs) {
      if (tab.entryId == entryId) {
        tab
          ..groupId = entry.groupId
          ..folderId = entry.folderId;
      }
    }
    if (pendingFolderId.isNotEmpty && pendingGroupId == groupId) {
      pendingFolderId = entry.folderId;
    }
    notifyListeners();
    _schedulePersist();
    _scheduleDraft();
  }

  /// 把条目移动到另一个条目之前（同一容器内排序 / 跨容器移动）。
  void moveEntryBefore(String entryId, String targetId) {
    final from = collections.indexWhere((item) => item.id == entryId);
    final to = collections.indexWhere((item) => item.id == targetId);
    if (from < 0 || to < 0 || from == to) return;
    final entry = collections[from];
    final target = collections[to];
    entry
      ..groupId = target.groupId
      ..folderId = target.folderId;
    collections.removeAt(from);
    final insertAt = collections.indexWhere((item) => item.id == targetId);
    collections.insert(insertAt < 0 ? collections.length : insertAt, entry);
    notifyListeners();
    _schedulePersist();
  }

  CollectionEntry? duplicateEntry(String id) {
    final source = collections.where((item) => item.id == id).firstOrNull;
    if (source == null) return null;
    final copy = CollectionEntry(
      name: '${source.name} 副本',
      mode: source.mode,
      groupId: source.groupId,
      folderId: source.folderId,
      description: source.description,
      variables: source.variables.map((item) => item.copy()).toList(),
      request: source.request?.copy(),
      ws: source.ws?.copy(),
    );
    collections.insert(0, copy);
    notifyListeners();
    _schedulePersist();
    return copy;
  }

  CollectionFolder? duplicateFolder(String id) {
    final source = folders.where((item) => item.id == id).firstOrNull;
    if (source == null) return null;
    final copy = CollectionFolder(
      groupId: source.groupId,
      parentId: source.parentId,
      name: '${source.name} 副本',
      description: source.description,
      variables: source.variables.map((item) => item.copy()).toList(),
      auth: source.auth.copy(),
    );
    folders.add(copy);
    final children = folders.where((item) => item.parentId == source.id).toList();
    for (final child in children) {
      folders.add(CollectionFolder(
        groupId: child.groupId,
        parentId: copy.id,
        name: child.name,
        description: child.description,
        variables: child.variables.map((item) => item.copy()).toList(),
        auth: child.auth.copy(),
      ));
    }
    for (final entry in collections.where((item) => item.folderId == source.id)) {
      collections.insert(
        0,
        CollectionEntry(
          name: entry.name,
          mode: entry.mode,
          groupId: entry.groupId,
          folderId: copy.id,
          description: entry.description,
          variables: entry.variables.map((item) => item.copy()).toList(),
          request: entry.request?.copy(),
          ws: entry.ws?.copy(),
        ),
      );
    }
    notifyListeners();
    _schedulePersist();
    return copy;
  }

  CollectionGroup? duplicateGroup(String id) {
    final source = groups.where((item) => item.id == id).firstOrNull;
    if (source == null) return null;
    final group = CollectionGroup(
      name: '${source.name} 副本',
      mode: source.mode,
      description: source.description,
      variables: source.variables.map((item) => item.copy()).toList(),
      auth: source.auth.copy(),
    );
    groups.add(group);
    final folderMap = <String, String>{};
    for (final folder in folders.where((item) => item.groupId == id)) {
      final copy = CollectionFolder(
        groupId: group.id,
        parentId: folderMap[folder.parentId] ?? '',
        name: folder.name,
        description: folder.description,
        variables: folder.variables.map((item) => item.copy()).toList(),
        auth: folder.auth.copy(),
      );
      folderMap[folder.id] = copy.id;
      folders.add(copy);
    }
    for (final entry in collections.where((item) => item.groupId == id)) {
      collections.insert(
        0,
        CollectionEntry(
          name: entry.name,
          mode: entry.mode,
          groupId: group.id,
          folderId: folderMap[entry.folderId] ?? '',
          description: entry.description,
          variables: entry.variables.map((item) => item.copy()).toList(),
          request: entry.request?.copy(),
          ws: entry.ws?.copy(),
        ),
      );
    }
    notifyListeners();
    _schedulePersist();
    return group;
  }

  void updateEntryMeta(
    String id, {
    String? name,
    String? description,
    String? groupId,
    String? folderId,
  }) {
    final entry = collections.where((item) => item.id == id).firstOrNull;
    if (entry == null) return;
    if (name != null && name.trim().isNotEmpty) entry.name = name.trim();
    if (description != null) entry.description = description;
    if (groupId != null) entry.groupId = groupId;
    if (folderId != null) entry.folderId = folderId;
    for (final tab in tabs) {
      if (tab.entryId == id && name != null && name.trim().isNotEmpty) {
        tab.name = name.trim();
      }
    }
    notifyListeners();
    _schedulePersist();
    _scheduleDraft();
  }

  void addExample(String entryId, RequestExample example) {
    final entry = collections.where((item) => item.id == entryId).firstOrNull;
    if (entry == null) return;
    entry.examples.insert(0, example);
    notifyListeners();
    _schedulePersist();
  }

  void deleteExample(String entryId, String exampleId) {
    final entry = collections.where((item) => item.id == entryId).firstOrNull;
    if (entry == null) return;
    entry.examples.removeWhere((item) => item.id == exampleId);
    notifyListeners();
    _schedulePersist();
  }

  void setGlobals(List<KV> list) {
    globals = list;
    notifyListeners();
    _schedulePersist();
  }

  void updateSettings(AppSettings next) {
    settings = next;
    notifyListeners();
    _schedulePersist();
  }

  void setCollectionAuth(String groupId, AuthConfig auth) {
    final group = groups.where((item) => item.id == groupId).firstOrNull;
    if (group == null) return;
    group.auth = auth;
    notifyListeners();
    _schedulePersist();
  }

  void setCollectionVariables(String groupId, List<KV> vars) {
    final group = groups.where((item) => item.id == groupId).firstOrNull;
    if (group == null) return;
    group.variables = vars;
    notifyListeners();
    _schedulePersist();
  }

  void setFolderAuth(String folderId, AuthConfig auth) {
    final folder = folders.where((item) => item.id == folderId).firstOrNull;
    if (folder == null) return;
    folder.auth = auth;
    notifyListeners();
    _schedulePersist();
  }

  void setFolderVariables(String folderId, List<KV> vars) {
    final folder = folders.where((item) => item.id == folderId).firstOrNull;
    if (folder == null) return;
    folder.variables = vars;
    notifyListeners();
    _schedulePersist();
  }

  /// 可用的变量名，用于 `{{` 自动补全。
  List<String> get varNames {
    final names = <String>{};
    for (final list in [globals, env.vars]) {
      for (final item in list) {
        if (item.k.trim().isNotEmpty) names.add(item.k.trim());
      }
    }
    for (final group in groups) {
      for (final item in group.variables) {
        if (item.k.trim().isNotEmpty) names.add(item.k.trim());
      }
    }
    for (final folder in folders) {
      for (final item in folder.variables) {
        if (item.k.trim().isNotEmpty) names.add(item.k.trim());
      }
    }
    names.addAll(runtimeVars.keys);
    final sorted = names.toList()..sort();
    return sorted;
  }


  /* ------------------------------------------------------------------ */
  /* 环境 / Cookie                                                       */
  /* ------------------------------------------------------------------ */

  void updateEnv(String name, List<KV> vars) => updateEnvById(env.id, name, vars);

  void updateEnvById(String id, String name, List<KV> vars) {
    final next = Env(id: id, name: name, vars: vars);
    final index = environments.indexWhere((item) => item.id == id);
    if (index >= 0) {
      environments[index] = next;
    } else {
      environments.add(next);
    }
    if (environments.length == 1) activeEnvId = next.id;
    notifyListeners();
    _schedulePersist();
  }

  void switchEnv(String id) {
    if (activeEnvId == id) return;
    if (!environments.any((item) => item.id == id)) return;
    activeEnvId = id;
    notifyListeners();
    _schedulePersist();
  }

  Env createEnv(String name) {
    final created = Env(name: name.trim().isEmpty ? '新环境' : name.trim());
    environments.add(created);
    activeEnvId = created.id;
    notifyListeners();
    _schedulePersist();
    return created;
  }

  void duplicateEnv(String id) {
    final source = environments.where((item) => item.id == id).firstOrNull;
    if (source == null) return;
    final copy = source.copy()
      ..id = newId()
      ..name = '${source.name} 副本';
    environments.add(copy);
    activeEnvId = copy.id;
    notifyListeners();
    _schedulePersist();
  }

  bool deleteEnv(String id) {
    if (environments.length <= 1) return false;
    environments.removeWhere((item) => item.id == id);
    if (activeEnvId == id) activeEnvId = environments.first.id;
    notifyListeners();
    _schedulePersist();
    return true;
  }

  void deleteCookie(int index) {
    if (index >= 0 && index < cookies.length) {
      cookies.removeAt(index);
      notifyListeners();
      _schedulePersist();
    }
  }

  void clearCookies() {
    cookies.clear();
    notifyListeners();
    _schedulePersist();
  }

  /* ------------------------------------------------------------------ */
  /* 集合运行器 / 定时监控                                                */
  /* ------------------------------------------------------------------ */

  /// 按集合结构深度优先展开要运行的 HTTP 请求。
  List<CollectionEntry> runnerEntries(String groupId) {
    final result = <CollectionEntry>[];
    final seen = <String>{};

    void walk(String folderId) {
      final entries = folderId.isEmpty
          ? entriesInGroupRoot(groupId)
          : entriesInFolder(folderId);
      for (final entry in entries) {
        if (entry.mode == 'http' && seen.add(entry.id)) result.add(entry);
      }
      final children =
          folderId.isEmpty ? rootFolders(groupId) : childFolders(folderId);
      for (final child in children) {
        walk(child.id);
      }
    }

    walk('');
    for (final entry in entriesFor('http')) {
      if (entry.groupId == groupId && seen.add(entry.id)) result.add(entry);
    }
    return result;
  }

  Future<RunReport> runCollection({
    required String groupId,
    int iterations = 1,
    List<Map<String, String>> dataRows = const [],
    bool stopOnError = false,
  }) async {
    if (runningCollection) {
      throw HttpFailure('已有集合正在运行');
    }
    final group = groups.where((item) => item.id == groupId).firstOrNull;
    final entries = runnerEntries(groupId);
    if (entries.isEmpty) {
      throw HttpFailure('该集合下没有可运行的 HTTP 请求');
    }
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final steps = <RunStepResult>[];
    final savedGroup = _ctxGroupId;
    final savedFolder = _ctxFolderId;
    final savedEntry = _ctxEntryId;
    final savedExtra = _ctxExtra;
    final savedRuntime = Map<String, String>.of(runtimeVars);

    runningCollection = true;
    _stopRunner = false;
    runnerProgress = '准备运行';
    notifyListeners();

    try {
      final rounds = iterations <= 0 ? 1 : iterations;
      for (var round = 0; round < rounds; round++) {
        if (_stopRunner) break;
        final data = dataRows.isEmpty
            ? const <String, String>{}
            : dataRows[round % dataRows.length];
        var index = 0;
        var guard = 0;
        final limit = entries.length * 4;
        while (index >= 0 && index < entries.length && guard < limit) {
          if (_stopRunner) break;
          final entry = entries[index];
          runnerProgress =
              '第 ${round + 1}/$rounds 轮 · ${index + 1}/${entries.length} ${entry.name}';
          notifyListeners();
          final result = await _runEntryHeadless(entry, round + 1, data);
          steps.add(result);
          var nextIndex = index + 1;
          final next = scriptNextRequest;
          scriptNextRequest = null;
          if (next != null) {
            if (next.toLowerCase() == 'null') {
              break;
            }
            final found = entries.indexWhere(
              (item) => item.name == next || item.id == next,
            );
            if (found >= 0) nextIndex = found;
          }
          if (stopOnError && !result.passed) break;
          index = nextIndex;
          guard += 1;
        }
      }
    } finally {
      stopwatch.stop();
      _ctxGroupId = savedGroup;
      _ctxFolderId = savedFolder;
      _ctxEntryId = savedEntry;
      _ctxExtra = savedExtra;
      runtimeVars
        ..clear()
        ..addAll(savedRuntime);
      runningCollection = false;
      runnerProgress = '';
    }

    final report = RunReport(
      collectionName: group?.name ?? '集合',
      startedAt: startedAt,
      durationMs: stopwatch.elapsedMilliseconds,
      iterations: iterations <= 0 ? 1 : iterations,
      steps: steps,
      cancelled: _stopRunner,
      dataSource: dataRows.isEmpty ? null : '数据文件 ${dataRows.length} 行',
    );
    lastReport = report;
    notifyListeners();
    _schedulePersist();
    return report;
  }

  void stopRunner() {
    if (!runningCollection) return;
    _stopRunner = true;
    runnerProgress = '正在停止…';
    notifyListeners();
  }

  Future<RunStepResult> _runEntryHeadless(
    CollectionEntry entry,
    int iteration,
    Map<String, String> extra,
  ) async {
    final work = entry.request?.copy() ?? ApiRequest();
    _ctxGroupId = entry.groupId;
    _ctxFolderId = entry.folderId;
    _ctxEntryId = entry.id;
    _ctxExtra = extra;

    String url = '';
    int? status;
    var ms = 0;
    String body = '';
    String? error;
    final failures = <String>[];

    try {
      await _refreshOAuthIfNeeded(work);
      final pre = scripts.run(
        source: work.preScript,
        input: ScriptInput(
          method: work.method,
          url: work.url,
          bodyMode: work.bodyMode,
          body: work.bodyMode == 'json' || work.bodyMode == 'text'
              ? work.body
              : buildBody(work),
          headers: _scriptHeaders(work),
          env: varMap,
          vars: Map.of(runtimeVars),
          globals: _mapOf(globals),
          collection: _collectionVars(entry.groupId),
          requestName: entry.name,
          event: 'prerequest',
        ),
      );
      _applyHeadlessOutcome(pre, work, failures, prerequest: true);

      url = buildUrl(work);
      final headers = collectHeaders(work);
      final payload = buildBody(work);
      final multipart =
          work.bodyMode == 'form-data' ? buildMultipart(work) : <FormRow>[];
      _applyContentType(work, headers);
      final limit = work.options.timeoutSeconds;
      final result = await http.send(
        method: work.method,
        url: url,
        headers: headers,
        body: payload,
        multipart: multipart,
        followRedirects: work.options.followRedirects,
        rejectUnauthorized: work.options.rejectUnauthorized,
        cookies: work.options.manageCookies ? cookies : <CookieEntry>[],
        timeout: limit <= 0 ? const Duration(days: 365) : Duration(seconds: limit),
        settings: settings,
        rawBody: work.bodyMode == 'grpc' ? buildGrpcFrame(work) : null,
      );
      status = result.status;
      ms = result.ms;
      body = result.text ?? '';

      final post = scripts.run(
        source: work.postScript,
        input: ScriptInput(
          method: work.method,
          url: url,
          bodyMode: work.bodyMode,
          body: payload,
          headers: headers,
          env: varMap,
          vars: Map.of(runtimeVars),
          globals: _mapOf(globals),
          collection: _collectionVars(entry.groupId),
          requestName: entry.name,
          event: 'test',
        ),
        response: result,
      );
      _applyHeadlessOutcome(post, work, failures, prerequest: false);
    } catch (err) {
      error = err is HttpFailure ? err.message : '$err';
    }

    return RunStepResult(
      entryId: entry.id,
      name: entry.name,
      method: work.method,
      url: url,
      status: status,
      ms: ms,
      iteration: iteration,
      failures: failures,
      error: error,
      body: body,
    );
  }

  void _applyHeadlessOutcome(
    ScriptOutcome? outcome,
    ApiRequest work,
    List<String> failures, {
    required bool prerequest,
  }) {
    if (outcome == null) return;
    if (outcome.error != null && outcome.error!.isNotEmpty) {
      failures.add('脚本错误：${outcome.error}');
    }
    for (final test in outcome.tests) {
      if (!test.passed) {
        failures.add(test.error == null ? '断言失败：${test.name}' : '${test.name}：${test.error}');
      }
    }
    if (outcome.nextRequest != null && outcome.nextRequest!.isNotEmpty) {
      scriptNextRequest = outcome.nextRequest;
    }
    if (outcome.env.isNotEmpty) {
      env.vars = outcome.env.entries
          .map((entry) => KV(k: entry.key, v: entry.value))
          .toList();
    }
    if (outcome.vars.isNotEmpty) runtimeVars = Map.of(outcome.vars);
    if (outcome.globals.isNotEmpty) {
      globals = outcome.globals.entries
          .map((entry) => KV(k: entry.key, v: entry.value))
          .toList();
    }
    if (!prerequest) return;
    if (outcome.method.trim().isNotEmpty) {
      work.method = outcome.method.trim().toUpperCase();
    }
    if (outcome.url.trim().isNotEmpty) work.url = outcome.url;
    if (outcome.headers.isNotEmpty) {
      work.headers = outcome.headers
          .map((header) => KV(on: !header.disabled, k: header.key, v: header.value))
          .toList();
    }
    work.bodyMode = _normalizeBodyMode(outcome.bodyMode, outcome.body);
    if (work.bodyMode == 'json' || work.bodyMode == 'text') {
      work.body = outcome.body;
    }
  }

  void _applyContentType(ApiRequest work, Map<String, String> headers) {
    if (_hasHeader(headers, 'content-type')) return;
    switch (work.bodyMode) {
      case 'json':
      case 'graphql':
        headers['Content-Type'] = 'application/json';
        break;
      case 'text':
        headers['Content-Type'] = 'text/plain; charset=utf-8';
        break;
      case 'form':
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
        break;
      case 'grpc':
        headers['Content-Type'] =
            'application/grpc-web+${work.grpcBinary ? 'proto' : 'json'}';
        headers['x-grpc-web'] = '1';
        headers['accept'] = 'application/grpc-web+proto';
        break;
    }
  }

  String exportReportJson() {
    final report = lastReport;
    if (report == null) return '{}';
    return const JsonEncoder.withIndent('  ').convert(report.toJson());
  }

  List<MonitorConfig> monitorsFor(String groupId) =>
      monitors.where((item) => item.groupId == groupId).toList();

  MonitorConfig addMonitor({
    required String groupId,
    String name = '定时监控',
    int intervalMinutes = 30,
    int iterations = 1,
  }) {
    final monitor = MonitorConfig(
      groupId: groupId,
      name: name,
      intervalMinutes: intervalMinutes <= 0 ? 30 : intervalMinutes,
      iterations: iterations <= 0 ? 1 : iterations,
    );
    monitors.add(monitor);
    _syncMonitors();
    notifyListeners();
    _schedulePersist();
    return monitor;
  }

  void updateMonitor(MonitorConfig next) {
    final index = monitors.indexWhere((item) => item.id == next.id);
    if (index < 0) return;
    monitors[index] = next;
    _syncMonitors();
    notifyListeners();
    _schedulePersist();
  }

  void deleteMonitor(String id) {
    monitors.removeWhere((item) => item.id == id);
    _syncMonitors();
    notifyListeners();
    _schedulePersist();
  }

  Future<void> runMonitorNow(MonitorConfig monitor) async {
    if (runningCollection) return;
    try {
      final report = await runCollection(
        groupId: monitor.groupId,
        iterations: monitor.iterations,
      );
      monitor
        ..lastRunAt = DateTime.now().millisecondsSinceEpoch
        ..lastPassed = report.passed
        ..lastTotal = report.total
        ..lastError = report.failed > 0 ? '${report.failed} 个请求未通过' : '';
    } catch (err) {
      monitor
        ..lastRunAt = DateTime.now().millisecondsSinceEpoch
        ..lastError = '$err';
    }
    notifyListeners();
    _schedulePersist();
  }

  void _syncMonitors() {
    for (final timer in _monitorTimers.values) {
      timer.cancel();
    }
    _monitorTimers.clear();
    for (final monitor in monitors) {
      if (!monitor.enabled) continue;
      final interval = monitor.intervalMinutes <= 0 ? 30 : monitor.intervalMinutes;
      _monitorTimers[monitor.id] = Timer.periodic(
        Duration(minutes: interval),
        (_) => runMonitorNow(monitor),
      );
    }
  }

  /* ------------------------------------------------------------------ */
  /* 导入 / 导出                                                          */
  /* ------------------------------------------------------------------ */

  Map<String, dynamic> exportAstra() => {
        'app': appName,
        'version': version,
        'exportedAt': DateTime.now().toIso8601String(),
        'env': env.toJson(),
        'environments': environments.map((item) => item.toJson()).toList(),
        'activeEnvId': activeEnvId,
        'groups': groups.map((item) => item.toJson()).toList(),
        'folders': folders.map((item) => item.toJson()).toList(),
        'collections': collections.map((item) => item.toJson()).toList(),
        'cookies': cookies.map((item) => item.toJson()).toList(),
        'globals': globals.map((item) => item.toJson()).toList(),
        'settings': settings.toJson(),
        'monitors': monitors.map((item) => item.toJson()).toList(),
      };

  Map<String, dynamic> exportPostman() => toPostman(collections, env);

  Map<String, dynamic> exportOpenApi() => toOpenApi(collections, env);

  /// 返回导入结果描述；无法识别时抛出异常。
  String importData(dynamic data) {
    final kind = detectKind(data);
    if (kind == 'unknown' || data is! Map) {
      throw const FormatException('无法识别的文件格式，支持 Postman、OpenAPI 3、Swagger 2 和 Astra 导出文件');
    }
    if (kind == 'astra') {
      return _importAstra(Map<String, dynamic>.from(data));
    }
    final doc = Map<String, dynamic>.from(data);
    final result = kind == 'postman' ? importPostman(doc) : importOpenApi(doc);
    var merged = 0;
    for (final variable in result.variables) {
      final key = variable.k.trim();
      if (key.isEmpty) continue;
      final index = env.vars.indexWhere((item) => item.k.trim() == key);
      if (index >= 0) {
        env.vars[index].v = variable.v;
      } else {
        env.vars.add(variable);
      }
      merged += 1;
    }
    if (env.vars.length > 1) {
      env.vars.removeWhere((item) => item.k.isEmpty && item.v.isEmpty);
      if (env.vars.isEmpty) env.vars.add(KV());
    }
    collections.insertAll(0, result.collections);
    notifyListeners();
    _schedulePersist();
    final label = kind == 'postman' ? 'Postman' : 'OpenAPI';
    return '已从 $label 导入 ${result.collections.length} 个请求，合并 $merged 个变量';
  }

  String _importAstra(Map<String, dynamic> data) {
    var count = 0;
    final rawGroups = data['groups'];
    if (rawGroups is List) {
      for (final raw in rawGroups.whereType<Map>()) {
        final group = CollectionGroup.fromJson(Map<String, dynamic>.from(raw));
        if (!groups.any((item) => item.id == group.id)) groups.add(group);
      }
    }
    final rawFolders = data['folders'];
    if (rawFolders is List) {
      for (final raw in rawFolders.whereType<Map>()) {
        final folder = CollectionFolder.fromJson(Map<String, dynamic>.from(raw));
        if (!folders.any((item) => item.id == folder.id)) folders.add(folder);
      }
    }
    final list = data['collections'];
    if (list is List) {
      for (final raw in list.whereType<Map>()) {
        collections.insert(0, CollectionEntry.fromJson(Map<String, dynamic>.from(raw)));
        count += 1;
      }
    }
    final rawEnvs = data['environments'];
    if (rawEnvs is List && rawEnvs.isNotEmpty) {
      for (final raw in rawEnvs.whereType<Map>()) {
        final env = Env.fromJson(Map<String, dynamic>.from(raw));
        final index = environments.indexWhere((item) => item.id == env.id);
        if (index >= 0) {
          environments[index] = env;
        } else {
          environments.add(env);
        }
      }
      final importedActive = '${data['activeEnvId'] ?? ''}';
      if (environments.any((item) => item.id == importedActive)) {
        activeEnvId = importedActive;
      }
    } else if (data['env'] is Map) {
      final imported = Env.fromJson(Map<String, dynamic>.from(data['env'] as Map));
      if (imported.vars.isNotEmpty) updateEnv(imported.name, imported.vars);
    }
    final cookieRaw = data['cookies'];
    if (cookieRaw is List) {
      for (final raw in cookieRaw.whereType<Map>()) {
        final cookie = CookieEntry.fromJson(Map<String, dynamic>.from(raw));
        final exists = cookies.any((item) =>
            item.name == cookie.name &&
            item.domain == cookie.domain &&
            item.path == cookie.path);
        if (!exists) cookies.add(cookie);
      }
    }
    final globalRaw = data['globals'];
    if (globalRaw is List) {
      for (final raw in globalRaw.whereType<Map>()) {
        final variable = KV.fromJson(Map<String, dynamic>.from(raw));
        if (variable.k.trim().isEmpty) continue;
        final index = globals.indexWhere((item) => item.k.trim() == variable.k.trim());
        if (index >= 0) {
          globals[index].v = variable.v;
        } else {
          globals.add(variable);
        }
      }
    }
    if (data['settings'] is Map) {
      settings = AppSettings.fromJson(
        Map<String, dynamic>.from(data['settings'] as Map),
      );
    }
    final monitorRaw = data['monitors'];
    if (monitorRaw is List) {
      for (final raw in monitorRaw.whereType<Map>()) {
        final monitor = MonitorConfig.fromJson(Map<String, dynamic>.from(raw));
        final index = monitors.indexWhere((item) => item.id == monitor.id);
        if (index >= 0) {
          monitors[index] = monitor;
        } else {
          monitors.add(monitor);
        }
      }
      _syncMonitors();
    }
    notifyListeners();
    _schedulePersist();
    final groupCount = rawGroups is List ? rawGroups.length : 0;
    final envCount = rawEnvs is List ? rawEnvs.length : 0;
    return '已从 Astra 备份导入 $count 个请求、$groupCount 个集合、$envCount 个环境';
  }

  /* ------------------------------------------------------------------ */
  /* 持久化                                                              */
  /* ------------------------------------------------------------------ */

  Future<void> load() async {
    final workspace = await storage.read('workspace.json');
    if (workspace != null) {
      final rawCollections = workspace['collections'];
      if (rawCollections is List) {
        collections = rawCollections
            .whereType<Map>()
            .map((item) => CollectionEntry.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
      final rawHistory = workspace['history'];
      if (rawHistory is List) {
        history = rawHistory
            .whereType<Map>()
            .map((item) => HistoryEntry.fromJson(Map<String, dynamic>.from(item)))
            .take(80)
            .toList();
      }
      final rawGroups = workspace['groups'];
      if (rawGroups is List) {
        groups = rawGroups
            .whereType<Map>()
            .map((item) => CollectionGroup.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
      final rawFolders = workspace['folders'];
      if (rawFolders is List) {
        folders = rawFolders
            .whereType<Map>()
            .map((item) => CollectionFolder.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
      final rawEnvs = workspace['environments'];
      if (rawEnvs is List && rawEnvs.isNotEmpty) {
        environments = rawEnvs
            .whereType<Map>()
            .map((item) => Env.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        final savedActive = '${workspace['activeEnvId'] ?? ''}';
        activeEnvId = environments.any((item) => item.id == savedActive)
            ? savedActive
            : environments.first.id;
      } else {
        final rawEnv = workspace['env'];
        if (rawEnv is Map) {
          environments = [Env.fromJson(Map<String, dynamic>.from(rawEnv))];
          activeEnvId = environments.first.id;
        }
      }
      if (environments.isEmpty) {
        environments = [Env()];
        activeEnvId = environments.first.id;
      }
      final rawCookies = workspace['cookies'];
      if (rawCookies is List) {
        cookies = rawCookies
            .whereType<Map>()
            .map((item) => CookieEntry.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
      final rawGlobals = workspace['globals'];
      if (rawGlobals is List) {
        globals = rawGlobals
            .whereType<Map>()
            .map((item) => KV.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
      if (workspace['settings'] is Map) {
        settings = AppSettings.fromJson(
          Map<String, dynamic>.from(workspace['settings'] as Map),
        );
      }
      final rawMonitors = workspace['monitors'];
      if (rawMonitors is List) {
        monitors = rawMonitors
            .whereType<Map>()
            .map((item) => MonitorConfig.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    }

    final draft = await storage.read('draft.json');
    if (draft != null) {
      final rawTabs = draft['tabs'];
      if (rawTabs is List && rawTabs.isNotEmpty) {
        tabs = rawTabs
            .whereType<Map>()
            .map((item) => WorkspaceTab.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        final savedActive = '${draft['activeTabId'] ?? ''}';
        activeTabId = tabs.any((tab) => tab.id == savedActive) ? savedActive : tabs.first.id;
        final tab = activeTab!;
        mode = tab.mode;
        selectedId = tab.entryId.isEmpty ? null : tab.entryId;
        pendingGroupId = tab.groupId;
        pendingFolderId = tab.folderId;
      } else {
        if (draft['mode'] == 'ws') mode = 'ws';
        if (draft['request'] is Map) {
          request = ApiRequest.fromJson(Map<String, dynamic>.from(draft['request'] as Map));
        }
        if (draft['ws'] is Map) {
          ws = WsConfig.fromJson(Map<String, dynamic>.from(draft['ws'] as Map));
        }
        if (draft['selectedId'] is String) selectedId = draft['selectedId'] as String;
        if (draft['pendingGroupId'] is String) pendingGroupId = draft['pendingGroupId'] as String;
        if (draft['pendingFolderId'] is String) {
          pendingFolderId = draft['pendingFolderId'] as String;
        }
      }
    }

    notifyListeners();
    _syncMonitors();
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), () {
      storage.write('workspace.json', {
        'collections': collections.map((item) => item.toJson()).toList(),
        'groups': groups.map((item) => item.toJson()).toList(),
        'folders': folders.map((item) => item.toJson()).toList(),
        'history': history.map((item) => item.toJson()).toList(),
        'env': env.toJson(),
        'environments': environments.map((item) => item.toJson()).toList(),
        'activeEnvId': activeEnvId,
        'cookies': cookies.map((item) => item.toJson()).toList(),
        'globals': globals.map((item) => item.toJson()).toList(),
        'settings': settings.toJson(),
        'monitors': monitors.map((item) => item.toJson()).toList(),
      });
    });
  }

  void _scheduleDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), () {
      storage.write('draft.json', {
        'mode': mode,
        'activeTabId': activeTabId,
        'tabs': tabs.map((item) => item.toJson()).toList(),
        'request': request.toJson(),
        'ws': ws.toJson(),
        'selectedId': selectedId,
        'pendingGroupId': pendingGroupId,
        'pendingFolderId': pendingFolderId,
      });
    });
  }

  /// 输入框内容变化时调用，触发草稿持久化。
  void touch() {
    _scheduleDraft();
  }

  void showToast(String message) {
    toast = message;
    notifyListeners();
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      toast = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _draftTimer?.cancel();
    _toastTimer?.cancel();
    for (final timer in _monitorTimers.values) {
      timer.cancel();
    }
    _sseSession?.close();
    wsService.close();
    super.dispose();
  }
}

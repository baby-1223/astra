import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/api_service.dart';
import 'services/converters.dart';
import 'services/file_io.dart';
import 'services/oauth.dart';
import 'services/script_service.dart';
import 'services/secret_vault.dart';
import 'services/storage.dart';
import 'services/ws_service.dart';

part 'state_parts/curl.dart';
part 'state_parts/import_export.dart';
part 'state_parts/persistence.dart';
part 'state_parts/runner.dart';
part 'state_parts/ws_session.dart';

class AppState extends ChangeNotifier
    with _WorkspacePersistence, _WorkspaceTransfer, _CurlTools, _RunnerTools, _WsSession {
  static const String appName = 'Astra';
  static const String version = '2.1.7';

  /// workspace.json / draft.json 的结构版本，加载时用于迁移。
  static const int workspaceSchemaVersion = 1;

  final Storage storage = Storage();
  final SecretStore secretStore = KeychainSecretStore();
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

  /// 运行器实时结果，运行过程中逐条追加
  final List<RunStepResult> runSteps = [];

  /// 本轮运行开始时间（毫秒），0 表示尚未运行
  int runStartedAt = 0;
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
    storage.onError = _onStorageError;
    storage.onRecovered = (message) => showToast(message);
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

  /// 集合树中当前选中的节点，供 Rename / Duplicate / Delete 等快捷键使用。
  /// kind 取值：group / folder / entry；空字符串表示没有选中树节点。
  String selectedNodeKind = '';
  String selectedNodeId = '';

  void selectTreeNode(String kind, String id) {
    selectedNodeKind = kind;
    selectedNodeId = id;
    notifyListeners();
  }

  CollectionGroup? get selectedGroupNode => selectedNodeKind == 'group'
      ? groups.where((item) => item.id == selectedNodeId).firstOrNull
      : null;

  CollectionFolder? get selectedFolderNode => selectedNodeKind == 'folder'
      ? folders.where((item) => item.id == selectedNodeId).firstOrNull
      : null;

  CollectionEntry? get selectedEntryNode => selectedNodeKind == 'entry'
      ? collections.where((item) => item.id == selectedNodeId).firstOrNull
      : null;

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
      VariableScope('Globals', globals),
    ];
    for (final group in groups) {
      scopes.add(VariableScope('Collection · ${group.name}', group.variables));
    }
    for (final folder in folders) {
      final path = folderPath(folder.id);
      scopes.add(VariableScope('Folder · $path', folder.variables));
    }
    scopes.add(VariableScope('Environment · ${env.name}', env.vars));
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
    if (req.auth.type != 'inherit') return 'This Request';
    var folder = folders.where((item) => item.id == _activeFolderId).firstOrNull;
    var guard = 0;
    while (folder != null && guard < 32) {
      final current = folder;
      if (current.auth.type != 'inherit') return 'Folder · ${current.name}';
      folder = current.parentId.isEmpty
          ? null
          : folders.where((item) => item.id == current.parentId).firstOrNull;
      guard += 1;
    }
    final group = groups.where((item) => item.id == _activeGroupId).firstOrNull;
    if (group != null && group.auth.type != 'inherit') return 'Collection · ${group.name}';
    return 'None';
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
    if (raw.isEmpty) throw HttpFailure('Enter a request URL');
    if (!RegExp(r'^[a-zA-Z][\w+.-]*://').hasMatch(raw)) {
      raw = 'http://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) throw HttpFailure('Invalid request URL');

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
            throw HttpFailure('GraphQL variables are not valid JSON');
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
      throw HttpFailure('gRPC payload is not valid base64');
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
        retries: effective.options.retries,
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
    sseStatus = 'Connecting…';
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
      sseStatus = 'Connected (HTTP ${session.status}), waiting for events…';
      _pushHistory(request.copy(), url, session.status, 0);
      session.events.listen(
        (event) {
          sseLog.add(event);
          sseCount += 1;
          if (sseLog.length > 600) sseLog.removeAt(0);
          notifyListeners();
        },
        onError: (Object err) {
          sseStatus = 'Connection error: $err';
          sseRunning = false;
          _sseSession = null;
          notifyListeners();
        },
        onDone: () {
          sseStatus = 'Connection closed';
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
      sseStatus ??= 'Stopped';
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
    if (auth.type != 'oauth2') return 'Set the authorization type to OAuth 2.0 first';
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
    if (tokenUrl.isEmpty) return 'Enter the Token endpoint URL first';
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
      return result.error ?? 'Failed to get token';
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
    return url.isEmpty ? 'Untitled Request' : url;
  }

  /* ------------------------------------------------------------------ */
  /* WebSocket                                                           */
  /* ------------------------------------------------------------------ */


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
    showToast('Saved');
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
      targetMode == 'ws' ? 'Untitled Connection' : 'Untitled API';

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

  /// Switches to the previous (-1) or next (+1) tab in the current mode.
  void selectRelativeTab(int offset) {
    final modeTabs = tabsFor(mode);
    final index = modeTabs.indexWhere((item) => item.id == activeTabId);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= modeTabs.length) return;
    activateTab(modeTabs[target].id);
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
    showToast('New ${targetMode == 'ws' ? 'connection' : 'API request'} created here. Fill it in and press ⌘ / Ctrl + S to save');
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
    showToast('Request created from cURL');
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
      name: name.trim().isEmpty ? 'Untitled Request' : name.trim(),
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
      name: name.trim().isEmpty ? 'New Collection' : name.trim(),
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
      name: name.trim().isEmpty ? 'New Folder' : name.trim(),
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
      name: '${source.name} copy',
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
      name: '${source.name} copy',
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
    for (final entry
        in collections.where((item) => item.folderId == source.id).toList()) {
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
      name: '${source.name} copy',
      mode: source.mode,
      description: source.description,
      variables: source.variables.map((item) => item.copy()).toList(),
      auth: source.auth.copy(),
    );
    groups.add(group);
    final folderMap = <String, String>{};
    for (final folder
        in folders.where((item) => item.groupId == id).toList()) {
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
    for (final entry
        in collections.where((item) => item.groupId == id).toList()) {
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

  /// 整体替换当前环境的变量（用于 .env / CSV 导入）。
  void setActiveEnvVars(List<KV> vars) {
    env.vars = vars;
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

  void setGroupStarred(String groupId, bool starred) {
    final group = groups.where((item) => item.id == groupId).firstOrNull;
    if (group == null || group.starred == starred) return;
    group.starred = starred;
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
    final created = Env(name: name.trim().isEmpty ? 'New Environment' : name.trim());
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
      ..name = '${source.name} copy';
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

  /// 一键还原：删除本地持久化数据并回到首次启动状态。
  Future<void> resetToInitialState() async {
    _persistTimer?.cancel();
    _draftTimer?.cancel();
    for (final timer in _monitorTimers.values) {
      timer.cancel();
    }
    _monitorTimers.clear();
    final requestIds = <String>{
      for (final item in collections) item.id,
      for (final item in history) item.id,
    };
    await forgetRequestSecrets(requestIds, secretStore);
    await storage.delete('workspace.json');
    await storage.delete('draft.json');

    mode = 'http';
    tabs = [];
    activeTabId = '';
    _fallbackRequest = ApiRequest();
    _fallbackWs = WsConfig();
    environments = [Env()];
    activeEnvId = environments.first.id;
    groups = [];
    folders = [];
    pendingGroupId = '';
    pendingFolderId = '';
    collections = [];
    history = [];
    cookies = [];
    globals = [];
    settings = AppSettings();
    monitors = [];
    selectedId = null;
    response = null;
    responseError = null;
    sending = false;
    responseCookies = [];
    responseHistory.clear();
    runningCollection = false;
    runnerProgress = '';
    lastReport = null;
    runSteps.clear();
    runStartedAt = 0;
    _stopRunner = false;
    sseRunning = false;
    sseStatus = null;
    sseLog.clear();
    sseCount = 0;
    wsReceived = 0;
    wsError = null;
    toast = null;
    notifyListeners();
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

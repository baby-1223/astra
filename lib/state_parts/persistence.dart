part of '../state.dart';

/// 工作区持久化：加载、防抖落盘、串行写入与结构迁移。
///
/// 依赖 [AppState] 提供的工作区状态；拆出独立 mixin，避免 `state.dart`
/// 持续膨胀，同时保持成员仍属于同一个库，可直接访问私有状态。
mixin _WorkspacePersistence on ChangeNotifier {
  Storage get storage;
  SecretStore get secretStore;
  List<CollectionEntry> get collections;
  set collections(List<CollectionEntry> value);
  List<CollectionGroup> get groups;
  set groups(List<CollectionGroup> value);
  List<CollectionFolder> get folders;
  set folders(List<CollectionFolder> value);
  List<HistoryEntry> get history;
  set history(List<HistoryEntry> value);
  Env get env;
  List<Env> get environments;
  set environments(List<Env> value);
  String get activeEnvId;
  set activeEnvId(String value);
  List<CookieEntry> get cookies;
  set cookies(List<CookieEntry> value);
  List<KV> get globals;
  set globals(List<KV> value);
  AppSettings get settings;
  set settings(AppSettings value);
  List<MonitorConfig> get monitors;
  set monitors(List<MonitorConfig> value);
  MockServerConfig get mockServer;
  set mockServer(MockServerConfig value);
  String get mode;
  set mode(String value);
  List<WorkspaceTab> get tabs;
  set tabs(List<WorkspaceTab> value);
  String get activeTabId;
  set activeTabId(String value);
  WorkspaceTab? get activeTab;
  ApiRequest get request;
  set request(ApiRequest value);
  WsConfig get ws;
  set ws(WsConfig value);
  String? get selectedId;
  set selectedId(String? value);
  String get pendingGroupId;
  set pendingGroupId(String value);
  String get pendingFolderId;
  set pendingFolderId(String value);

  void _syncMonitors();
  void showToast(String message);

  Timer? _persistTimer;
  Timer? _draftTimer;
  int _persistSeq = 0;
  int _draftSeq = 0;

  /// 串行化落盘，避免异步脱敏期间旧数据后写入而覆盖新数据。
  Future<void> _writeChain = Future<void>.value();
  String? _lastStorageError;
  DateTime? _lastStorageErrorAt;

  Future<void> load() async {
    final stored = await storage.read('workspace.json');
    var workspace = stored;
    if (workspace != null) {
      await hydrateSecrets(workspace, secretStore);
      workspace = _migrateWorkspace(workspace);
    }
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
      if (workspace['mockServer'] is Map) {
        mockServer = MockServerConfig.fromJson(
          Map<String, dynamic>.from(workspace['mockServer'] as Map),
        );
      }
    }

    var draft = await storage.read('draft.json');
    if (draft != null) {
      await hydrateSecrets(draft, secretStore);
    }
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

  void schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), _persistWorkspace);
  }

  Future<void> _persistWorkspace() async {
    final seq = ++_persistSeq;
    final payload = <String, dynamic>{
      'schemaVersion': AppState.workspaceSchemaVersion,
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
      'mockServer': mockServer.toJson(),
    };
    final data = await _redact(payload);
    if (seq != _persistSeq) return;
    await _writeFile('workspace.json', data);
  }

  void _scheduleDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), _persistDraft);
  }

  Future<void> _persistDraft() async {
    final seq = ++_draftSeq;
    final payload = <String, dynamic>{
      'schemaVersion': AppState.workspaceSchemaVersion,
      'mode': mode,
      'activeTabId': activeTabId,
      'tabs': tabs.map((item) => item.toJson()).toList(),
      'request': request.toJson(),
      'ws': ws.toJson(),
      'selectedId': selectedId,
      'pendingGroupId': pendingGroupId,
      'pendingFolderId': pendingFolderId,
    };
    final data = await _redact(payload);
    if (seq != _draftSeq) return;
    await _writeFile('draft.json', data);
  }

  /// 按调用顺序串行写入，保证最后一次修改最终落盘。
  Future<void> _writeFile(String name, Map<String, dynamic> data) {
    final next = _writeChain.then((_) => storage.write(name, data));
    _writeChain = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<Map<String, dynamic>> _redact(Map<String, dynamic> payload) async {
    try {
      return await redactSecrets(payload, secretStore);
    } catch (_) {
      return payload;
    }
  }

  Map<String, dynamic> _migrateWorkspace(Map<String, dynamic> source) {
    final migrated = Map<String, dynamic>.from(source);
    // v0 文件没有 schemaVersion，结构与 v1 一致；后续版本在此追加迁移。
    migrated['schemaVersion'] = AppState.workspaceSchemaVersion;
    return migrated;
  }

  void _onStorageError(String message) {
    final now = DateTime.now();
    final last = _lastStorageErrorAt;
    if (message == _lastStorageError &&
        last != null &&
        now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastStorageError = message;
    _lastStorageErrorAt = now;
    showToast(message);
  }
}

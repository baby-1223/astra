part of '../state.dart';

/// 工作区导入与导出（Astra / Postman / OpenAPI）。
mixin _WorkspaceTransfer on ChangeNotifier {
  List<CollectionEntry> get collections;
  List<CollectionGroup> get groups;
  List<CollectionFolder> get folders;
  Env get env;
  List<Env> get environments;
  String get activeEnvId;
  set activeEnvId(String value);
  List<CookieEntry> get cookies;
  List<KV> get globals;
  AppSettings get settings;
  set settings(AppSettings value);
  List<MonitorConfig> get monitors;
  MockServerConfig get mockServer;
  MockServerService get mockServerService;

  void updateEnv(String name, List<KV> vars);
  void _syncMonitors();
  void schedulePersist();

  Map<String, dynamic> exportAstra() => {
        'app': AppState.appName,
        'version': AppState.version,
        'schemaVersion': AppState.workspaceSchemaVersion,
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
        'mockServer': mockServer.toJson(),
      };

  Map<String, dynamic> exportPostman() => toPostman(collections, env);

  Map<String, dynamic> exportOpenApi() => toOpenApi(collections, env);

  /// 返回导入结果描述；无法识别时抛出异常。
  String importData(dynamic data) {
    final kind = detectKind(data);
    if (kind == 'unknown' || data is! Map) {
      throw const FormatException('Unrecognized file format. Supported formats: Postman, OpenAPI 3, Swagger 2 and Astra export');
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
    groups.addAll(result.groups);
    folders.addAll(result.folders);
    for (final global in result.globals) {
      if (!globals.any((item) => item.k.trim() == global.k.trim())) {
        globals.add(global);
      }
    }
    if (result.environments.isNotEmpty) {
      environments.addAll(result.environments);
      activeEnvId = result.environments.first.id;
    }
    collections.insertAll(0, result.collections);
    notifyListeners();
    schedulePersist();
    final label = kind == 'postman' ? 'Postman' : 'OpenAPI';
    final created = <String>[
      if (result.groups.isNotEmpty) '${result.groups.length} collection(s)',
      if (result.folders.isNotEmpty) '${result.folders.length} folder(s)',
      if (result.environments.isNotEmpty) '${result.environments.length} environment(s)',
    ];
    final suffix = created.isEmpty ? '' : ', created ${created.join(', ')}';
    return 'Imported ${result.collections.length} requests from $label, merged $merged variables$suffix';
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
    var importedMocks = 0;
    if (data['mockServer'] is Map) {
      final incoming = MockServerConfig.fromJson(
        Map<String, dynamic>.from(data['mockServer'] as Map),
      );
      mockServer.port = incoming.port;
      mockServerService.update(mockServer);
      for (final route in incoming.routes) {
        final index = mockServer.routes.indexWhere((item) => item.id == route.id);
        if (index >= 0) {
          mockServer.routes[index] = route;
        } else {
          mockServer.routes.add(route);
        }
        importedMocks += 1;
      }
      mockServerService.update(mockServer);
    }
    notifyListeners();
    schedulePersist();
    final groupCount = rawGroups is List ? rawGroups.length : 0;
    final envCount = rawEnvs is List ? rawEnvs.length : 0;
    final suffix = importedMocks > 0 ? ', $importedMocks mock routes' : '';
    return 'Imported $count requests, $groupCount collections, $envCount environments$suffix from Astra backup';
  }
}

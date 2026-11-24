part of '../state.dart';

/// 集合运行器与定时监控。
mixin _RunnerTools on ChangeNotifier {
  List<CollectionEntry> get collections;
  List<CollectionGroup> get groups;
  List<CollectionEntry> entriesFor(String mode);
  List<CollectionEntry> entriesInGroupRoot(String groupId);
  List<CollectionEntry> entriesInFolder(String folderId);
  List<CollectionFolder> rootFolders(String groupId);
  List<CollectionFolder> childFolders(String parentId);
  List<CookieEntry> get cookies;
  List<KV> get globals;
  set globals(List<KV> value);
  List<MonitorConfig> get monitors;
  Map<String, Timer> get _monitorTimers;
  Env get env;
  AppSettings get settings;
  HttpService get http;
  ScriptService get scripts;
  Map<String, String> get varMap;
  Map<String, String> get runtimeVars;
  set runtimeVars(Map<String, String> value);
  String? get scriptNextRequest;
  set scriptNextRequest(String? value);
  bool get runningCollection;
  set runningCollection(bool value);
  bool get _stopRunner;
  set _stopRunner(bool value);
  List<RunStepResult> get runSteps;
  int get runStartedAt;
  set runStartedAt(int value);
  String get runnerProgress;
  set runnerProgress(String value);
  RunReport? get lastReport;
  set lastReport(RunReport? value);
  String get _ctxGroupId;
  set _ctxGroupId(String value);
  String get _ctxFolderId;
  set _ctxFolderId(String value);
  String get _ctxEntryId;
  set _ctxEntryId(String value);
  Map<String, String> get _ctxExtra;
  set _ctxExtra(Map<String, String> value);

  Future<void> _refreshOAuthIfNeeded(ApiRequest work);
  Map<String, String> collectHeaders([ApiRequest? req]);
  String buildUrl([ApiRequest? req]);
  String buildBody([ApiRequest? req]);
  List<FormRow> buildMultipart([ApiRequest? req]);
  Uint8List buildGrpcFrame(ApiRequest source);
  Map<String, String> _scriptHeaders(ApiRequest req);
  Map<String, String> _mapOf(List<KV> list);
  Map<String, String> _collectionVars(String groupId);
  String _normalizeBodyMode(String mode, String body);
  bool _hasHeader(Map<String, String> headers, String name);
  void schedulePersist();

  List<CollectionEntry> runnerEntries(String groupId, {String folderId = ''}) {
    final result = <CollectionEntry>[];
    final seen = <String>{};

    void walk(String currentFolderId) {
      final entries = currentFolderId.isEmpty
          ? entriesInGroupRoot(groupId)
          : entriesInFolder(currentFolderId);
      for (final entry in entries) {
        if (entry.mode == 'http' && seen.add(entry.id)) result.add(entry);
      }
      final children = currentFolderId.isEmpty
          ? rootFolders(groupId)
          : childFolders(currentFolderId);
      for (final child in children) {
        walk(child.id);
      }
    }

    if (folderId.isEmpty) {
      walk('');
      for (final entry in entriesFor('http')) {
        if (entry.groupId == groupId && seen.add(entry.id)) result.add(entry);
      }
    } else {
      walk(folderId);
    }
    return result;
  }

  Future<RunReport> runCollection({
    required String groupId,
    String folderId = '',
    int iterations = 1,
    int delayMs = 0,
    List<Map<String, String>> dataRows = const [],
    bool stopOnError = false,
  }) async {
    if (runningCollection) {
      throw HttpFailure('A collection is already running');
    }
    final group = groups.where((item) => item.id == groupId).firstOrNull;
    final entries = runnerEntries(groupId, folderId: folderId);
    if (entries.isEmpty) {
      throw HttpFailure('This collection has no HTTP requests to run');
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
    runSteps.clear();
    runStartedAt = DateTime.now().millisecondsSinceEpoch;
    runnerProgress = 'Preparing to run';
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
          if (delayMs > 0 && steps.isNotEmpty) {
            await Future<void>.delayed(Duration(milliseconds: delayMs));
            if (_stopRunner) break;
          }
          final entry = entries[index];
          runnerProgress =
              'Iteration ${round + 1}/$rounds · ${index + 1}/${entries.length} ${entry.name}';
          notifyListeners();
          final result = await _runEntryHeadless(entry, round + 1, data);
          steps.add(result);
          runSteps.add(result);
          notifyListeners();
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
      collectionName: group?.name ?? 'Collection',
      startedAt: startedAt,
      durationMs: stopwatch.elapsedMilliseconds,
      iterations: iterations <= 0 ? 1 : iterations,
      steps: steps,
      cancelled: _stopRunner,
      dataSource: dataRows.isEmpty ? null : 'Data file (${dataRows.length} rows)',
    );
    lastReport = report;
    notifyListeners();
    schedulePersist();
    return report;
  }

  void stopRunner() {
    if (!runningCollection) return;
    _stopRunner = true;
    runnerProgress = 'Stopping…';
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
    var testPassed = 0;
    var testTotal = 0;

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
      final preCounts = _applyHeadlessOutcome(pre, work, failures, prerequest: true);
      testPassed += preCounts.$1;
      testTotal += preCounts.$2;

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
        retries: work.options.retries,
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
      final postCounts = _applyHeadlessOutcome(post, work, failures, prerequest: false);
      testPassed += postCounts.$1;
      testTotal += postCounts.$2;
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
      testPassed: testPassed,
      testTotal: testTotal,
    );
  }

  (int, int) _applyHeadlessOutcome(
    ScriptOutcome? outcome,
    ApiRequest work,
    List<String> failures, {
    required bool prerequest,
  }) {
    if (outcome == null) return (0, 0);
    var passed = 0;
    if (outcome.error != null && outcome.error!.isNotEmpty) {
      failures.add('Script error: ${outcome.error}');
    }
    for (final test in outcome.tests) {
      if (test.passed) {
        passed += 1;
      } else {
        failures.add(test.error == null ? 'Assertion failed: ${test.name}' : '${test.name}: ${test.error}');
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
    if (prerequest) {
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
    return (passed, outcome.tests.length);
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
    String name = 'Scheduled Monitor',
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
    schedulePersist();
    return monitor;
  }

  void updateMonitor(MonitorConfig next) {
    final index = monitors.indexWhere((item) => item.id == next.id);
    if (index < 0) return;
    monitors[index] = next;
    _syncMonitors();
    notifyListeners();
    schedulePersist();
  }

  void deleteMonitor(String id) {
    monitors.removeWhere((item) => item.id == id);
    _syncMonitors();
    notifyListeners();
    schedulePersist();
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
        ..lastError = report.failed > 0 ? '${report.failed} request(s) failed' : '';
    } catch (err) {
      monitor
        ..lastRunAt = DateTime.now().millisecondsSinceEpoch
        ..lastError = '$err';
    }
    notifyListeners();
    schedulePersist();
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
}

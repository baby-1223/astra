import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/file_io.dart';
import '../state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Collection runner: executes the HTTP requests of a collection or folder in
/// order, with iterations, delays, data files and an exportable report.
Future<void> showRunnerDialog(
  BuildContext context,
  AppState state, {
  String? groupId,
  String? folderId,
}) async {
  var selectedGroup = groupId ??
      (state.groups.where((item) => item.mode == 'http').firstOrNull?.id ?? '');
  var selectedFolder = folderId ?? '';
  var iterationFilter = -1;
  var sortColumn = -1;
  var sortAscending = true;
  var failuresHeight = 150.0;
  var dataName = '';
  var continueOnFailure = true;
  final iterationsController = TextEditingController(text: '1');
  final delayController = TextEditingController(text: '0');
  final dataController = TextEditingController();

  Future<void> startRun(CollectionGroup? group, List<Map<String, String>> rows) async {
    if (state.runningCollection || group == null) return;
    try {
      await state.runCollection(
        groupId: group.id,
        folderId: selectedFolder,
        iterations: rows.isNotEmpty
            ? rows.length
            : (int.tryParse(iterationsController.text) ?? 1),
        delayMs: int.tryParse(delayController.text) ?? 0,
        dataRows: rows,
        stopOnError: !continueOnFailure,
      );
    } catch (err) {
      state.showToast('$err');
    }
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AnimatedBuilder(
      animation: state,
      builder: (ctx, _) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final groups = state.groupsFor('http');
          final group = groups.where((item) => item.id == selectedGroup).firstOrNull ??
              groups.firstOrNull;
          final entries = group == null
              ? <CollectionEntry>[]
              : state.runnerEntries(group.id, folderId: selectedFolder);
          final parsedData = _parseData(dataController.text);
          final steps = List<RunStepResult>.from(state.runSteps);
          if (sortColumn >= 0) {
            steps.sort((a, b) {
              final result = _compareSteps(a, b, sortColumn);
              return sortAscending ? result : -result;
            });
          }
          final visible = iterationFilter < 0
              ? steps
              : steps.where((step) => step.iteration == iterationFilter).toList();
          final failures = steps.where((step) => !step.passed).toList();
          final summary = _summaryOf(steps);
          final running = state.runningCollection;

          return AstraDialogShell(
            title: group == null ? 'Collection Runner' : 'Run ${group.name}',
            subtitle:
                'Requests run in collection order. Use a CSV or JSON data file to drive one iteration per row.',
            width: 1080,
            child: CallbackShortcuts(
              bindings: {
                SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
                    startRun(group, parsedData),
                SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
                    startRun(group, parsedData),
                SingleActivator(LogicalKeyboardKey.escape): () {
                  if (state.runningCollection) state.stopRunner();
                  Navigator.of(ctx).pop();
                },
              },
              child: Focus(
                autofocus: true,
                child: SizedBox(
                  height: 600,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 215,
                        child: groups.isEmpty
                            ? Text(
                                'No HTTP collections yet. Create one in the sidebar first.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AstraColors.faint,
                                ),
                              )
                            : ListView.builder(
                                itemCount: groups.length,
                                itemBuilder: (context, index) {
                                  final item = groups[index];
                                  final active = item.id == group?.id;
                                  final count =
                                      state.runnerEntries(item.id).length;
                                  return InkWell(
                                    onTap: () => setLocal(() {
                                      selectedGroup = item.id;
                                      selectedFolder = '';
                                      iterationFilter = -1;
                                    }),
                                    child: Container(
                                      margin: EdgeInsets.only(bottom: 6),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? AstraColors.accentSoft
                                            : AstraColors.overlay,
                                        border: Border.all(
                                          color: active
                                              ? AstraColors.accentBorder
                                              : AstraColors.line,
                                        ),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: active
                                                    ? AstraColors.accent
                                                    : AstraColors.text,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '$count',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AstraColors.faint,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _configBar(
                              ctx: ctx,
                              state: state,
                              group: group,
                              entries: entries,
                              running: running,
                              iterationsController: iterationsController,
                              delayController: delayController,
                              dataRows: parsedData,
                              dataName: dataName,
                              dataLocked: parsedData.isNotEmpty,
                              continueOnFailure: continueOnFailure,
                              onContinueChanged: (value) =>
                                  setLocal(() => continueOnFailure = value),
                              onDataLoaded: (name) =>
                                  setLocal(() => dataName = name),
                              onDataCleared: () => setLocal(() {
                                dataController.clear();
                                dataName = '';
                              }),
                              dataController: dataController,
                            ),
                            SizedBox(height: 12),
                            _summaryCards(summary),
                            SizedBox(height: 10),
                            Row(
                              children: [
                                Text(
                                  'Filter',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: AstraColors.muted,
                                  ),
                                ),
                                SizedBox(width: 8),
                                DropdownButton<int>(
                                  value: iterationFilter,
                                  dropdownColor: AstraColors.surface2,
                                  underline: SizedBox.shrink(),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: AstraColors.text,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: -1,
                                      child: Text('All Iterations'),
                                    ),
                                    for (final iteration in _iterationsOf(steps))
                                      DropdownMenuItem(
                                        value: iteration,
                                        child: Text('Iteration $iteration'),
                                      ),
                                  ],
                                  onChanged: (value) => setLocal(
                                    () => iterationFilter = value ?? -1,
                                  ),
                                ),
                                Spacer(),
                                Text(
                                  running
                                      ? state.runnerProgress
                                      : (steps.isEmpty
                                          ? 'Ready'
                                          : '${steps.length} request(s)'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: AstraColors.faint,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            Expanded(
                              flex: 3,
                              child: _resultsSection(
                                visible: visible,
                                hasAny: steps.isNotEmpty,
                                sortColumn: sortColumn,
                                sortAscending: sortAscending,
                                onSort: (index) => setLocal(() {
                                  if (sortColumn == index) {
                                    sortAscending = !sortAscending;
                                  } else {
                                    sortColumn = index;
                                    sortAscending = true;
                                  }
                                }),
                              ),
                            ),
                            MouseRegion(
                              cursor: SystemMouseCursors.resizeUpDown,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragUpdate: (details) => setLocal(() {
                                  failuresHeight = (failuresHeight -
                                          details.delta.dy)
                                      .clamp(90.0, 360.0);
                                }),
                                child: Container(
                                  height: 9,
                                  alignment: Alignment.center,
                                  child: Container(
                                    height: 1,
                                    color: AstraColors.line,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: failuresHeight,
                              child: _failuresSection(failures),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              GhostButton(
                label: 'Export Report',
                icon: Icons.download_outlined,
                onPressed: steps.isEmpty || running
                    ? null
                    : () async {
                        final path = await saveJsonFile(
                          'astra-runner-'
                          '${(group?.name ?? 'collection').replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-')}-'
                          '${DateTime.now().millisecondsSinceEpoch}.json',
                          {
                            'name': group?.name ?? 'Collection',
                            'exportedAt': DateTime.now().toIso8601String(),
                            'summary': {
                              'totalRuns': summary.totalRuns,
                              'passedTests': summary.passedTests,
                              'failedTests': summary.failedTests,
                              'failedRequests': summary.failedRequests,
                              'durationMs': summary.durationMs,
                              'averageResponseMs': summary.averageMs,
                              'responseSizeBytes': summary.responseBytes,
                            },
                            'results': [
                              for (final step in steps)
                                {
                                  'iteration': step.iteration,
                                  'request': step.name,
                                  'method': step.method,
                                  'status': step.status,
                                  'timeMs': step.ms,
                                  'passed': step.passed,
                                  'error': step.error,
                                  'failures': step.failures,
                                },
                            ],
                            'failures': [
                              for (final step in failures)
                                {
                                  'iteration': step.iteration,
                                  'request': step.name,
                                  'status': step.status,
                                  'reason': _failureReason(step),
                                },
                            ],
                          },
                        );
                        if (path != null) state.showToast('Report exported');
                      },
              ),
              SizedBox(width: 8),
              GhostButton(
                label: 'Stop',
                icon: Icons.stop_circle_outlined,
                onPressed: running ? state.stopRunner : null,
              ),
              SizedBox(width: 8),
              GradientButton(
                label: 'Run',
                icon: Icons.play_arrow_rounded,
                onPressed: running || group == null
                    ? null
                    : () => startRun(group, parsedData),
              ),
              SizedBox(width: 8),
              GhostButton(
                label: 'Close',
                onPressed: () {
                  if (state.runningCollection) state.stopRunner();
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          );
        },
      ),
    ),
  );

  iterationsController.dispose();
  delayController.dispose();
  dataController.dispose();
}

class _RunSummary {
  final int totalRuns;
  final int passedTests;
  final int failedTests;
  final int failedRequests;
  final int durationMs;
  final int averageMs;
  final int responseBytes;

  _RunSummary({
    required this.totalRuns,
    required this.passedTests,
    required this.failedTests,
    required this.failedRequests,
    required this.durationMs,
    required this.averageMs,
    required this.responseBytes,
  });
}

_RunSummary _summaryOf(List<RunStepResult> steps) {
  var passedTests = 0;
  var failedTests = 0;
  var failedRequests = 0;
  var totalMs = 0;
  var size = 0;
  for (final step in steps) {
    passedTests += step.testPassed;
    failedTests += (step.testTotal - step.testPassed).clamp(0, 1 << 31);
    if (!step.passed) failedRequests += 1;
    totalMs += step.ms;
    size += utf8.encode(step.body).length;
  }
  return _RunSummary(
    totalRuns: steps.length,
    passedTests: passedTests,
    failedTests: failedTests,
    failedRequests: failedRequests,
    durationMs: totalMs,
    averageMs: steps.isEmpty ? 0 : totalMs ~/ steps.length,
    responseBytes: size,
  );
}

List<int> _iterationsOf(List<RunStepResult> steps) {
  final values = steps.map((step) => step.iteration).toSet().toList()..sort();
  return values;
}

int _compareSteps(RunStepResult a, RunStepResult b, int column) {
  switch (column) {
    case 0:
      return a.iteration.compareTo(b.iteration);
    case 1:
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    case 2:
      return a.method.compareTo(b.method);
    case 3:
      return (a.status ?? 0).compareTo(b.status ?? 0);
    case 4:
      return a.ms.compareTo(b.ms);
    case 5:
      return a.testPassed.compareTo(b.testPassed);
    case 6:
      return _resultLabel(a).compareTo(_resultLabel(b));
  }
  return 0;
}

String _resultLabel(RunStepResult step) =>
    step.error ?? (step.passed ? 'PASS' : 'FAIL');

String _failureReason(RunStepResult step) {
  if (step.error != null) return step.error!;
  if (step.failures.isNotEmpty) return step.failures.join('; ');
  return 'Failed';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Widget _configBar({
  required BuildContext ctx,
  required AppState state,
  required CollectionGroup? group,
  required List<CollectionEntry> entries,
  required bool running,
  required TextEditingController iterationsController,
  required TextEditingController delayController,
  required TextEditingController dataController,
  required List<Map<String, String>> dataRows,
  required String dataName,
  required bool dataLocked,
  required bool continueOnFailure,
  required ValueChanged<bool> onContinueChanged,
  required ValueChanged<String> onDataLoaded,
  required VoidCallback onDataCleared,
}) {
  Widget numberField(TextEditingController controller, String hint) {
    return SizedBox(
      width: 86,
      height: 32,
      child: TextField(
        controller: controller,
        enabled: !running,
        keyboardType: TextInputType.number,
        style: TextStyle(fontSize: 12),
        decoration: astraInput(
          hint: hint,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }

  return Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('Runs', style: TextStyle(fontSize: 10.5, color: AstraColors.muted)),
      numberField(iterationsController, '1'),
      Text('Delay', style: TextStyle(fontSize: 10.5, color: AstraColors.muted)),
      numberField(delayController, '0'),
      SizedBox(
        height: 32,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: continueOnFailure,
              activeColor: AstraColors.accent,
              onChanged: running ? null : (value) => onContinueChanged(value ?? true),
            ),
            Text('Continue', style: TextStyle(fontSize: 11.5)),
          ],
        ),
      ),
      GhostButton(
        label: 'Data File',
        icon: Icons.upload_file,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        onPressed: running
            ? null
            : () async {
                final file = await pickUploadFile();
                if (file == null) return;
                try {
                  final text = await File(file.path).readAsString();
                  dataController.text = text;
                  onDataLoaded(file.name);
                } catch (err) {
                  state.showToast('Unable to read file: $err');
                }
              },
      ),
      GhostButton(
        label: 'Clear',
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        onPressed: running || (dataName.isEmpty && dataController.text.isEmpty)
            ? null
            : onDataCleared,
      ),
      if (dataName.isNotEmpty)
        Text(
          '$dataName - ${dataRows.length} data row(s)',
          style: TextStyle(fontSize: 10.5, color: AstraColors.faint),
        ),
      if (entries.isEmpty)
        Text(
          'No HTTP requests in this selection',
          style: TextStyle(fontSize: 10.5, color: AstraColors.faint),
        ),
    ],
  );
}

Widget _summaryCards(_RunSummary summary) {
  final cards = <(String, String, Color?)>[
    ('Total Runs', '${summary.totalRuns}', null),
    ('Passed Tests', '${summary.passedTests}', null),
    ('Failed Tests', '${summary.failedTests}',
        summary.failedTests > 0 ? AstraColors.err : null),
    ('Failed Requests', '${summary.failedRequests}',
        summary.failedRequests > 0 ? AstraColors.err : null),
    ('Duration', '${summary.durationMs} ms', null),
    ('Avg Response', '${summary.averageMs} ms', null),
    ('Response Size', _formatBytes(summary.responseBytes), null),
  ];
  return LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth < 640 ? 2 : 4;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final card in cards)
            SizedBox(
              width: width,
              child: Container(
                padding: EdgeInsets.fromLTRB(10, 5, 10, 5),
                decoration: BoxDecoration(
                  border: Border.all(color: AstraColors.line),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.$1,
                      style: TextStyle(
                        fontSize: 10,
                        color: AstraColors.faint,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      card.$2,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: card.$3 ?? AstraColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

Widget _resultsSection({
  required List<RunStepResult> visible,
  required bool hasAny,
  required int sortColumn,
  required bool sortAscending,
  required ValueChanged<int> onSort,
}) {
  Widget header(String label, int flex, int index, {bool numeric = false}) {
    final active = sortColumn == index;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => onSort(index),
        child: Container(
          height: 26,
          padding: EdgeInsets.symmetric(horizontal: 10),
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisAlignment:
                numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: active ? AstraColors.text : AstraColors.muted,
                  ),
                ),
              ),
              if (active) ...[
                SizedBox(width: 2),
                Icon(
                  sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 11,
                  color: AstraColors.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget cell(
    String text,
    int flex, {
    bool numeric = false,
    Color? color,
    bool mono = false,
    String? tooltip,
  }) {
    final content = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: numeric ? TextAlign.right : TextAlign.left,
      style: mono
          ? monoStyle(size: 10.5, color: color ?? AstraColors.text)
          : TextStyle(fontSize: 11, color: color ?? AstraColors.text),
    );
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Align(
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: tooltip == null ? content : Tooltip(message: tooltip, child: content),
        ),
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Results',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
      SizedBox(height: 6),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AstraColors.line),
            borderRadius: BorderRadius.circular(7),
          ),
          child: !hasAny
              ? Center(
                  child: Text(
                    'No results yet — click Run to start',
                    style: TextStyle(fontSize: 11.5, color: AstraColors.faint),
                  ),
                )
              : Column(
                  children: [
                    Row(
                      children: [
                        header('Iteration', 1, 0),
                        header('Request', 4, 1),
                        header('Method', 1, 2),
                        header('Status', 1, 3),
                        header('Time', 1, 4, numeric: true),
                        header('Tests', 1, 5, numeric: true),
                        header('Result', 2, 6),
                      ],
                    ),
                    Divider(height: 1, color: AstraColors.line),
                    Expanded(
                      child: visible.isEmpty
                          ? Center(
                              child: Text(
                                'No results for this iteration',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AstraColors.faint,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final step = visible[index];
                                final result = _resultLabel(step);
                                final resultColor = step.passed
                                    ? AstraColors.ok
                                    : AstraColors.err;
                                return Container(
                                  height: 27,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom:
                                          BorderSide(color: AstraColors.overlay),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      cell('${step.iteration}', 1),
                                      cell(
                                        step.name,
                                        4,
                                        tooltip: step.name,
                                      ),
                                      cell(
                                        step.method,
                                        1,
                                        mono: true,
                                        color: AstraColors.accent2,
                                      ),
                                      cell(
                                        step.error != null
                                            ? 'ERR'
                                            : '${step.status ?? '—'}',
                                        1,
                                        mono: true,
                                        color: step.error != null
                                            ? AstraColors.err
                                            : statusColor(step.status),
                                      ),
                                      cell(
                                        '${step.ms} ms',
                                        1,
                                        numeric: true,
                                        color: AstraColors.muted,
                                      ),
                                      cell(
                                        step.testTotal == 0
                                            ? '-'
                                            : '${step.testPassed}/${step.testTotal}',
                                        1,
                                        numeric: true,
                                        color: AstraColors.muted,
                                      ),
                                      cell(
                                        result,
                                        2,
                                        color: resultColor,
                                        tooltip: result,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ),
    ],
  );
}

Widget _failuresSection(List<RunStepResult> failures) {
  Widget header(String label, int flex, {bool numeric = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 26,
        padding: EdgeInsets.symmetric(horizontal: 10),
        alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AstraColors.muted,
          ),
        ),
      ),
    );
  }

  Widget cell(
    String text,
    int flex, {
    bool numeric = false,
    Color? color,
    String? tooltip,
  }) {
    final content = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: numeric ? TextAlign.right : TextAlign.left,
      style: TextStyle(fontSize: 11, color: color ?? AstraColors.text),
    );
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Align(
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: tooltip == null ? content : Tooltip(message: tooltip, child: content),
        ),
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Failures',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
      SizedBox(height: 6),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AstraColors.line),
            borderRadius: BorderRadius.circular(7),
          ),
          child: failures.isEmpty
              ? Center(
                  child: Text(
                    'No failures',
                    style: TextStyle(fontSize: 11, color: AstraColors.faint),
                  ),
                )
              : Column(
                  children: [
                    Row(
                      children: [
                        header('Iteration', 1),
                        header('Request', 3),
                        header('Status', 1),
                        header('Reason', 6),
                      ],
                    ),
                    Divider(height: 1, color: AstraColors.line),
                    Expanded(
                      child: ListView.builder(
                        itemCount: failures.length,
                        itemBuilder: (context, index) {
                          final step = failures[index];
                          final reason = _failureReason(step);
                          return Container(
                            height: 27,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: AstraColors.overlay),
                              ),
                            ),
                            child: Row(
                              children: [
                                cell('${step.iteration}', 1),
                                cell(step.name, 3, tooltip: step.name),
                                cell(
                                  step.error != null
                                      ? 'ERR'
                                      : '${step.status ?? '—'}',
                                  1,
                                  color: AstraColors.err,
                                ),
                                cell(
                                  reason,
                                  6,
                                  color: AstraColors.err,
                                  tooltip: reason,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ],
  );
}

/// Parses a CSV (with quotes) or JSON data file into rows of variables.
List<Map<String, String>> _parseData(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  if (text.startsWith('[') || text.startsWith('{')) {
    try {
      final decoded = jsonDecode(text);
      final list = decoded is List ? decoded : [decoded];
      return list
          .whereType<Map>()
          .map((row) => row.map((key, value) => MapEntry('$key', '$value')))
          .toList();
    } catch (_) {
      return const [];
    }
  }
  final rows = _parseCsv(text);
  if (rows.length < 2) return const [];
  final headers = rows.first;
  return rows.skip(1).map((row) {
    final map = <String, String>{};
    for (var i = 0; i < headers.length; i++) {
      map[headers[i].trim()] = i < row.length ? row[i] : '';
    }
    return map;
  }).toList();
}

List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final buffer = StringBuffer();
  var quoted = false;

  void endField() {
    row.add(buffer.toString());
    buffer.clear();
  }

  void endRow() {
    endField();
    if (row.any((cell) => cell.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          buffer.write('"');
          i += 1;
        } else {
          quoted = false;
        }
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      endField();
    } else if (char == '\n') {
      endRow();
    } else if (char != '\r') {
      buffer.write(char);
    }
  }
  if (buffer.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

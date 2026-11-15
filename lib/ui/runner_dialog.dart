import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/file_io.dart';
import '../state.dart';
import 'bound_text_field.dart';
import 'theme.dart';
import 'widgets.dart';

/// 集合运行器：按顺序执行集合内的 HTTP 请求，支持重复、数据驱动与报告导出。
Future<void> showRunnerDialog(
  BuildContext context,
  AppState state, {
  String? groupId,
}) async {
  var tab = 0;
  var selectedGroup = groupId ??
      (state.groups.where((item) => item.mode == 'http').firstOrNull?.id ?? '');
  final iterations = TextEditingController(text: '1');
  final data = TextEditingController();
  var dataName = '';
  var stopOnError = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AnimatedBuilder(
      animation: state,
      builder: (ctx, _) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final groups = state.groupsFor('http');
          final group = groups.where((item) => item.id == selectedGroup).firstOrNull ??
              groups.firstOrNull;
          final entries =
              group == null ? <CollectionEntry>[] : state.runnerEntries(group.id);
          final report = state.lastReport;

          return AstraDialogShell(
          title: '集合运行器',
          subtitle: '按集合层级顺序执行请求，可使用 CSV / JSON 数据文件驱动多轮运行。',
          width: 920,
          child: SizedBox(
            height: 500,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 215,
                  child: groups.isEmpty
                      ? const Text(
                          '还没有 HTTP 集合，先在侧栏创建并添加请求。',
                          style: TextStyle(fontSize: 11.5, color: AstraColors.faint),
                        )
                      : ListView.builder(
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            final item = groups[index];
                            final active = item.id == group?.id;
                            final count = state.runnerEntries(item.id).length;
                            return InkWell(
                              onTap: () => setLocal(() {
                                selectedGroup = item.id;
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0x1638BDF8)
                                      : const Color(0x06FFFFFF),
                                  border: Border.all(
                                    color: active
                                        ? const Color(0x4038BDF8)
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
                                      style: const TextStyle(
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
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          AstraTabs(
                            items: const [
                              AstraTabItem('setup', '运行设置'),
                              AstraTabItem('report', '运行报告'),
                              AstraTabItem('monitor', '定时监控'),
                            ],
                            selected: ['setup', 'report', 'monitor'][tab],
                            compact: true,
                            onSelect: (id) => setLocal(
                              () => tab = ['setup', 'report', 'monitor'].indexOf(id),
                            ),
                          ),
                          const Spacer(),
                          if (group != null)
                            Text(
                              '${entries.length} 个请求',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AstraColors.faint,
                              ),
                            ),
                        ],
                      ),
                      const Divider(height: 14),
                      Expanded(
                        child: switch (tab) {
                          0 => _setupPane(
                              ctx: ctx,
                              state: state,
                              group: group,
                              entries: entries,
                              iterations: iterations,
                              data: data,
                              dataName: dataName,
                              stopOnError: stopOnError,
                              onDataName: (name) => dataName = name,
                              onStopOnError: (value) => stopOnError = value,
                            ),
                          1 => _reportPane(state, report),
                          _ => _monitorPane(ctx, state, group),
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (state.runningCollection)
              Text(
                state.runnerProgress,
                style: const TextStyle(fontSize: 10.5, color: AstraColors.muted),
              ),
            const Spacer(),
            GhostButton(
              label: '关闭',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
        },
      ),
    ),
  );
}

Widget _setupPane({
  required BuildContext ctx,
  required AppState state,
  required CollectionGroup? group,
  required List<CollectionEntry> entries,
  required TextEditingController iterations,
  required TextEditingController data,
  required String dataName,
  required bool stopOnError,
  required ValueChanged<String> onDataName,
  required ValueChanged<bool> onStopOnError,
}) {
  final parsed = _parseData(data.text);
  return SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('执行次数'),
        Row(
          children: [
            SizedBox(
              width: 120,
              child: BoundTextField(
                value: iterations.text,
                hint: '1',
                onChanged: (value) => iterations.text = value,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '执行 ${int.tryParse(iterations.text) ?? 1} 轮，共约 ${(int.tryParse(iterations.text) ?? 1) * entries.length} 次请求',
              style: const TextStyle(fontSize: 10.5, color: AstraColors.faint),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const SectionLabel('数据文件（CSV / JSON，可选）'),
            const Spacer(),
            GhostButton(
              label: '导入文件',
              icon: Icons.upload_file,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              onPressed: () async {
                final file = await pickUploadFile();
                if (file == null) return;
                try {
                  final text = await File(file.path).readAsString();
                  data.text = text;
                  onDataName(file.name);
                  state.showToast('已载入 ${file.name}：${_parseData(text).length} 行数据');
                } catch (err) {
                  state.showToast('读取失败：$err');
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 110,
          child: TextField(
            controller: data,
            expands: true,
            maxLines: null,
            minLines: null,
            style: monoStyle(size: 11.5, height: 1.5),
            decoration: astraInput(
              hint: 'user,token\nada,123\nlin,456\n\n或 JSON：[{"user":"ada","token":"123"}]',
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          parsed.isEmpty
              ? '留空则使用当前变量运行；每轮会把数据行合并进运行时变量。'
              : '已识别 ${parsed.length} 行数据，字段：${parsed.first.keys.join('、')}',
          style: const TextStyle(fontSize: 10.5, color: AstraColors.faint),
        ),
        if (dataName.isNotEmpty)
          Text(
            '来源：$dataName',
            style: const TextStyle(fontSize: 10, color: AstraColors.accent),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Checkbox(
              value: stopOnError,
              activeColor: AstraColors.accent,
              onChanged: (value) => onStopOnError(value ?? false),
            ),
            const Text('遇到失败立即停止', style: TextStyle(fontSize: 11.5)),
            const Spacer(),
            if (state.runningCollection)
              GhostButton(
                label: '停止运行',
                icon: Icons.stop_circle_outlined,
                onPressed: state.stopRunner,
              ),
            const SizedBox(width: 10),
            GradientButton(
              label: state.runningCollection ? '运行中…' : '开始运行',
              icon: Icons.play_arrow_rounded,
              onPressed: state.runningCollection || group == null
                  ? null
                  : () async {
                      try {
                        await state.runCollection(
                          groupId: group.id,
                          iterations: int.tryParse(iterations.text) ?? 1,
                          dataRows: parsed,
                          stopOnError: stopOnError,
                        );
                      } catch (err) {
                        state.showToast('$err');
                      }
                    },
            ),
          ],
        ),
        if (state.runningCollection)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(
              minHeight: 3,
              color: AstraColors.accent,
              backgroundColor: AstraColors.line,
            ),
          ),
        const SizedBox(height: 18),
        const SectionLabel('将要运行的请求'),
        ...entries.asMap().entries.map((item) {
          final index = item.key;
          final entry = item.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 10, color: AstraColors.faint),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    entry.request?.method ?? 'GET',
                    style: monoStyle(size: 10.5, color: AstraColors.accent2),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          );
        }),
        if (entries.isEmpty)
          const Text(
            '该集合还没有 HTTP 请求',
            style: TextStyle(fontSize: 11, color: AstraColors.faint),
          ),
      ],
    ),
  );
}

Widget _reportPane(AppState state, RunReport? report) {
  if (report == null) {
    return const Center(
      child: Text(
        '还没有运行记录',
        style: TextStyle(fontSize: 11.5, color: AstraColors.faint),
      ),
    );
  }
  final color = report.failed == 0 ? AstraColors.ok : AstraColors.err;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(
            '${(report.passRate * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${report.passed}/${report.total} 通过',
                style: const TextStyle(fontSize: 11.5),
              ),
              Text(
                '${report.iterations} 轮 · ${report.durationMs} ms · ${report.collectionName}',
                style: const TextStyle(fontSize: 10, color: AstraColors.faint),
              ),
            ],
          ),
          const Spacer(),
          GhostButton(
            label: '导出报告',
            icon: Icons.download_outlined,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            onPressed: () async {
              final path = await saveJsonFile(
                'astra-run-report.json',
                report.toJson(),
              );
              if (path != null) state.showToast('报告已导出');
            },
          ),
        ],
      ),
      const SizedBox(height: 10),
      Expanded(
        child: ListView.builder(
          itemCount: report.steps.length,
          itemBuilder: (context, index) {
            final step = report.steps[index];
            final ok = step.passed;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: ok ? const Color(0x0AFFFFFF) : const Color(0x14FB7185),
                border: Border.all(
                  color: ok ? AstraColors.line : const Color(0x33FB7185),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    ok ? Icons.check_circle_outline : Icons.error_outline,
                    size: 14,
                    color: ok ? AstraColors.ok : AstraColors.err,
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text(
                      step.method,
                      style: monoStyle(size: 10.5, color: AstraColors.accent2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        if (step.error != null)
                          Text(
                            step.error!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AstraColors.err,
                              height: 1.5,
                            ),
                          ),
                        if (step.failures.isNotEmpty)
                          Text(
                            step.failures.join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AstraColors.warn,
                              height: 1.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    step.status == null ? '—' : '${step.status}',
                    style: monoStyle(
                      size: 10.5,
                      color: statusColor(step.status),
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 58,
                    child: Text(
                      '${step.ms} ms',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 10, color: AstraColors.faint),
                    ),
                  ),
                  if (step.iteration > 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '#${step.iteration}',
                        style: const TextStyle(fontSize: 9.5, color: AstraColors.faint),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );
}

Widget _monitorPane(BuildContext ctx, AppState state, CollectionGroup? group) {
  final monitors = group == null ? <MonitorConfig>[] : state.monitorsFor(group.id);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              '监控会在 Astra 运行期间按间隔自动执行集合，并记录最近一次通过情况。',
              style: TextStyle(fontSize: 10.5, color: AstraColors.faint, height: 1.6),
            ),
          ),
          GradientButton(
            label: '新建监控',
            icon: Icons.add_alarm,
            onPressed: group == null
                ? null
                : () {
                    final monitor = state.addMonitor(
                      groupId: group.id,
                      name: '${group.name} 监控',
                      intervalMinutes: 30,
                    );
                    monitor.enabled = true;
                    state.updateMonitor(monitor);
                  },
          ),
        ],
      ),
      const SizedBox(height: 12),
      Expanded(
        child: monitors.isEmpty
            ? const Center(
                child: Text(
                  '还没有定时监控',
                  style: TextStyle(fontSize: 11.5, color: AstraColors.faint),
                ),
              )
            : ListView.builder(
                itemCount: monitors.length,
                itemBuilder: (context, index) {
                  final monitor = monitors[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0x08FFFFFF),
                      border: Border.all(color: AstraColors.line),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                monitor.name,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                monitor.lastRunAt == 0
                                    ? '尚未运行 · 每 ${monitor.intervalMinutes} 分钟'
                                    : '上次 ${_time(monitor.lastRunAt)} · ${monitor.lastPassed}/${monitor.lastTotal} 通过',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AstraColors.faint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DropdownButton<int>(
                          value: [5, 15, 30, 60, 120].contains(monitor.intervalMinutes)
                              ? monitor.intervalMinutes
                              : 30,
                          dropdownColor: AstraColors.surface2,
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(fontSize: 10.5, color: AstraColors.muted),
                          items: const [5, 15, 30, 60, 120]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text('每 $value 分钟'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            monitor.intervalMinutes = value;
                            state.updateMonitor(monitor);
                          },
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: monitor.enabled,
                          activeThumbColor: AstraColors.accent,
                          onChanged: (value) {
                            monitor.enabled = value;
                            state.updateMonitor(monitor);
                          },
                        ),
                        IconButton(
                          tooltip: '立即运行',
                          onPressed: state.runningCollection
                              ? null
                              : () => state.runMonitorNow(monitor),
                          icon: const Icon(Icons.play_circle_outline, size: 17),
                          color: AstraColors.muted,
                        ),
                        IconButton(
                          tooltip: '删除监控',
                          onPressed: () => state.deleteMonitor(monitor.id),
                          icon: const Icon(Icons.delete_outline, size: 17),
                          color: AstraColors.faint,
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

String _time(int ms) {
  final time = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// 解析 CSV（含引号）或 JSON 数据文件为多行变量。
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

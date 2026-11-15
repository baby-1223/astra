import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../state.dart';
import 'bound_text_field.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

/* ------------------------------------------------------------------ */
/* 变量总览                                                            */
/* ------------------------------------------------------------------ */

Future<void> showVariablesDialog(BuildContext context, AppState state) async {
  var index = 0;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final scopes = <_VarScope>[
          _VarScope(
            '全局',
            '所有请求可用的底层变量',
            state.globals,
            (rows) => state.setGlobals(rows),
            false,
          ),
          for (final group in state.groups)
            _VarScope(
              '集合 · ${group.name}',
              '仅该集合内的请求可用',
              group.variables,
              (rows) => state.setCollectionVariables(group.id, rows),
              false,
            ),
          for (final folder in state.folders)
            _VarScope(
              '文件夹 · ${state.folderPath(folder.id)}',
              '该文件夹及其子级可用，优先于集合变量',
              folder.variables,
              (rows) => state.setFolderVariables(folder.id, rows),
              false,
            ),
          _VarScope(
            '环境 · ${state.env.name}',
            '当前激活环境，优先级高于集合与文件夹',
            state.env.vars,
            null,
            true,
          ),
          _VarScope(
            '运行时',
            '脚本通过 pm.variables.set 写入，仅本次会话有效',
            [
              for (final entry in state.runtimeVars.entries)
                KV(k: entry.key, v: entry.value),
            ],
            null,
            true,
          ),
        ];
        final current = scopes[index.clamp(0, scopes.length - 1)];
        final merged = <String, String>{};
        for (final scope in scopes.take(scopes.length - 1)) {
          for (final item in scope.rows) {
            if (item.k.trim().isNotEmpty) merged[item.k.trim()] = item.v;
          }
        }
        merged.addAll(state.runtimeVars);

        return AstraDialogShell(
          title: '变量',
          subtitle: '优先级从低到高：全局 → 集合 → 文件夹 → 环境 → 请求 → 运行时。'
              '在输入框中键入 {{ 会自动补全变量名。',
          width: 860,
          child: SizedBox(
            height: 470,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 230,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(scopes.length, (i) {
                        final active = i == index;
                        final count =
                            scopes[i].rows.where((row) => row.k.trim().isNotEmpty).length;
                        return InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => setLocal(() => index = i),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                            decoration: BoxDecoration(
                              color: active ? const Color(0x1638BDF8) : const Color(0x06FFFFFF),
                              border: Border.all(
                                color: active ? const Color(0x4038BDF8) : AstraColors.line,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        scopes[i].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: active
                                              ? AstraColors.accent
                                              : AstraColors.text,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        scopes[i].description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          color: AstraColors.faint,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$count',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AstraColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              current.label,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (current.readOnly)
                            Text(
                              '只读',
                              style: TextStyle(
                                fontSize: 10,
                                color: AstraColors.faint,
                              ),
                            ),
                          if (current.label.startsWith('环境')) ...[
                            const SizedBox(width: 10),
                            GhostButton(
                              label: '环境管理',
                              icon: Icons.tune,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              onPressed: () => showEnvManagerDialog(ctx, state),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: current.readOnly
                              ? _ReadonlyVars(rows: current.rows, merged: merged)
                              : KVEditor(
                                  rows: current.rows,
                                  keyHint: '变量名',
                                  valueHint: '变量值',
                                  varNames: state.varNames,
                                  onChanged: () => current.onChanged?.call(current.rows),
                                  onAdd: () => setLocal(() => current.rows.add(KV())),
                                  onRemove: (i) => setLocal(() => current.rows.removeAt(i)),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Text(
              '共 ${state.varNames.length} 个可用变量',
              style: const TextStyle(fontSize: 10.5, color: AstraColors.faint),
            ),
            const Spacer(),
            GradientButton(
              label: '完成',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    ),
  );
}

class _VarScope {
  final String label;
  final String description;
  final List<KV> rows;
  final ValueChanged<List<KV>>? onChanged;
  final bool readOnly;

  _VarScope(this.label, this.description, this.rows, this.onChanged, this.readOnly);
}

class _ReadonlyVars extends StatelessWidget {
  final List<KV> rows;
  final Map<String, String> merged;

  const _ReadonlyVars({required this.rows, required this.merged});

  @override
  Widget build(BuildContext context) {
    final items = rows.where((row) => row.k.trim().isNotEmpty).toList();
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Text(
          '这一层还没有变量',
          style: TextStyle(fontSize: 11.5, color: AstraColors.faint),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items.map((row) {
        final effective = merged[row.k.trim()];
        final overridden = effective != row.v;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x06FFFFFF),
            border: Border.all(color: AstraColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 170,
                child: Text(
                  row.k,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(size: 11.5, color: AstraColors.accent),
                ),
              ),
              Expanded(
                child: Text(
                  row.v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(size: 11.5, color: AstraColors.muted),
                ),
              ),
              if (overridden)
                Text(
                  '被覆盖为 ${effective ?? ''}',
                  style: const TextStyle(fontSize: 9.5, color: AstraColors.warn),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/* ------------------------------------------------------------------ */
/* 请求预览（变量解析后）                                              */
/* ------------------------------------------------------------------ */

Future<void> showRequestPreviewDialog(BuildContext context, AppState state) async {
  final req = state.request;
  String url;
  Map<String, String> headers;
  String body;
  try {
    url = state.buildUrl(req);
    headers = state.collectHeaders(req);
    body = state.buildBody(req);
  } catch (err) {
    url = err.toString();
    headers = const {};
    body = '';
  }
  final rawUrl = req.url;
  final unresolved = <String>{
    ...RegExp(r'\{\{\s*([\w.-]+)\s*\}\}')
        .allMatches(rawUrl)
        .map((m) => m.group(0)!),
    ...RegExp(r'\{\{\s*([\w.-]+)\s*\}\}')
        .allMatches(req.body)
        .map((m) => m.group(0)!),
  };

  await showDialog<void>(
    context: context,
    builder: (ctx) => AstraDialogShell(
      title: '最终请求预览',
      subtitle: '已按当前变量作用域解析，用于发送前确认。',
      width: 720,
      child: SizedBox(
        height: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (unresolved.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x14F0C674),
                    border: Border.all(color: const Color(0x33F0C674)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '未解析变量：${unresolved.join('、')}',
                    style: const TextStyle(fontSize: 10.8, color: AstraColors.warn),
                  ),
                ),
              _previewBlock('${req.method} $url'),
              const SizedBox(height: 12),
              const SectionLabel('请求头'),
              _previewBlock(
                headers.isEmpty
                    ? '(空)'
                    : headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
              ),
              const SizedBox(height: 12),
              const SectionLabel('请求体'),
              _previewBlock(body.isEmpty ? '(空)' : body),
            ],
          ),
        ),
      ),
      actions: [
        GhostButton(
          label: '编辑变量',
          icon: Icons.data_object,
          onPressed: () => showVariablesDialog(ctx, state),
        ),
        GradientButton(
          label: '关闭',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
}

Widget _previewBlock(String text) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0xFF0B0F17),
      border: Border.all(color: AstraColors.line),
      borderRadius: BorderRadius.circular(9),
    ),
    child: SelectableText(
      text,
      style: monoStyle(size: 11.5, height: 1.55, color: const Color(0xFFD6DEF0)),
    ),
  );
}

/* ------------------------------------------------------------------ */
/* 批量编辑                                                            */
/* ------------------------------------------------------------------ */

Future<void> showBulkEditDialog(
  BuildContext context, {
  required String title,
  required List<KV> rows,
}) async {
  final controller = TextEditingController(
    text: rows
        .where((row) => row.k.trim().isNotEmpty)
        .map((row) => '${row.k}: ${row.v}')
        .join('\n'),
  );

  await showDialog<void>(
    context: context,
    builder: (ctx) => AstraDialogShell(
      title: title,
      subtitle: '每行一条，格式为 key: value；空行会被忽略。',
      width: 560,
      child: SizedBox(
        height: 320,
        child: TextField(
          controller: controller,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: monoStyle(size: 12, height: 1.55),
          decoration: astraInput(
            hint: 'Authorization: Bearer {{token}}\nAccept: application/json',
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ),
      actions: [
        GhostButton(
          label: '取消',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        GradientButton(
          label: '应用',
          onPressed: () {
            final parsed = <KV>[];
            for (final line in controller.text.split('\n')) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) continue;
              final index = trimmed.indexOf(':');
              if (index <= 0) {
                parsed.add(KV(k: trimmed, v: ''));
              } else {
                parsed.add(KV(
                  k: trimmed.substring(0, index).trim(),
                  v: trimmed.substring(index + 1).trim(),
                ));
              }
            }
            rows
              ..clear()
              ..addAll(parsed.isEmpty ? [KV()] : parsed);
            Navigator.of(ctx).pop();
          },
        ),
      ],
    ),
  );
}

/* ------------------------------------------------------------------ */
/* 响应 Diff                                                           */
/* ------------------------------------------------------------------ */

Future<void> showTextDiffDialog(
  BuildContext context, {
  required String title,
  required String before,
  required String after,
  required String beforeLabel,
  required String afterLabel,
}) async {
  final rows = _diffLines(before, after);
  final added = rows.where((row) => row.type == 1).length;
  final removed = rows.where((row) => row.type == -1).length;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AstraDialogShell(
      title: title,
      subtitle: '$beforeLabel → $afterLabel · 新增 $added 行，删除 $removed 行',
      width: 900,
      child: SizedBox(
        height: 460,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0F17),
            border: Border.all(color: AstraColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final color = switch (row.type) {
                1 => const Color(0xFF1B3A2A),
                -1 => const Color(0xFF3A1E24),
                _ => Colors.transparent,
              };
              final marker = switch (row.type) {
                1 => '+',
                -1 => '-',
                _ => ' ',
              };
              return Container(
                color: color,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        row.beforeNo?.toString() ?? '',
                        textAlign: TextAlign.right,
                        style: monoStyle(size: 10, color: AstraColors.faint),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        row.afterNo?.toString() ?? '',
                        textAlign: TextAlign.right,
                        style: monoStyle(size: 10, color: AstraColors.faint),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      marker,
                      style: monoStyle(
                        size: 11.5,
                        color: row.type == 0 ? AstraColors.faint : AstraColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        row.text.isEmpty ? ' ' : row.text,
                        style: monoStyle(
                          size: 11.5,
                          height: 1.5,
                          color: const Color(0xFFD6DEF0),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        GradientButton(label: '关闭', onPressed: () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}

class _DiffRow {
  final int type; // 1 新增，-1 删除，0 相同
  final String text;
  final int? beforeNo;
  final int? afterNo;

  _DiffRow(this.type, this.text, this.beforeNo, this.afterNo);
}

List<_DiffRow> _diffLines(String before, String after) {
  final a = before.split('\n');
  final b = after.split('\n');
  if (a.length > 900 || b.length > 900) {
    return [
      for (var i = 0; i < a.length; i++) _DiffRow(-1, a[i], i + 1, null),
      for (var i = 0; i < b.length; i++) _DiffRow(1, b[i], null, i + 1),
    ];
  }
  final table = List.generate(
    a.length + 1,
    (_) => List<int>.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      table[i][j] = a[i] == b[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1] ? table[i + 1][j] : table[i][j + 1]);
    }
  }
  final rows = <_DiffRow>[];
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      rows.add(_DiffRow(0, a[i], i + 1, j + 1));
      i += 1;
      j += 1;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      rows.add(_DiffRow(-1, a[i], i + 1, null));
      i += 1;
    } else {
      rows.add(_DiffRow(1, b[j], null, j + 1));
      j += 1;
    }
  }
  while (i < a.length) {
    rows.add(_DiffRow(-1, a[i], i + 1, null));
    i += 1;
  }
  while (j < b.length) {
    rows.add(_DiffRow(1, b[j], null, j + 1));
    j += 1;
  }
  return rows;
}

/* ------------------------------------------------------------------ */
/* 请求备注 / 描述                                                     */
/* ------------------------------------------------------------------ */

Future<void> showEntryMetaDialog(
  BuildContext context,
  AppState state,
  String entryId,
) async {
  final entry = state.collections.where((item) => item.id == entryId).firstOrNull;
  if (entry == null) return;
  final name = TextEditingController(text: entry.name);
  final description = TextEditingController(text: entry.description);

  await showDialog<void>(
    context: context,
    builder: (ctx) => AstraDialogShell(
      title: '请求信息',
      subtitle: '名称显示在标签页与侧栏，备注会显示在侧栏悬浮提示中。',
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BoundTextField(
            value: name.text,
            hint: '请求名称',
            onChanged: (value) => name.text = value,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: TextField(
              controller: description,
              expands: true,
              maxLines: null,
              minLines: null,
              style: const TextStyle(fontSize: 12, height: 1.55),
              decoration: astraInput(
                hint: '用途、依赖条件、注意事项…',
                contentPadding: const EdgeInsets.all(11),
              ),
            ),
          ),
        ],
      ),
      actions: [
        GhostButton(label: '取消', onPressed: () => Navigator.of(ctx).pop()),
        GradientButton(
          label: '保存',
          onPressed: () {
            state.updateEntryMeta(
              entryId,
              name: name.text,
              description: description.text,
            );
            Navigator.of(ctx).pop();
          },
        ),
      ],
    ),
  );
}

/* ------------------------------------------------------------------ */
/* 移动到集合 / 文件夹                                                 */
/* ------------------------------------------------------------------ */

Future<void> showMoveEntryDialog(
  BuildContext context,
  AppState state,
  String entryId,
) async {
  final entry = state.collections.where((item) => item.id == entryId).firstOrNull;
  if (entry == null) return;
  var groupId = entry.groupId;
  var folderId = entry.folderId;
  final groups = state.groupsFor(entry.mode);

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final folders = state.folders.where((item) => item.groupId == groupId).toList();
        if (!folders.any((item) => item.id == folderId)) folderId = '';

        return AstraDialogShell(
          title: '移动到…',
          subtitle: '选择目标集合与文件夹，不同集合的请求会自动切换分组。',
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('目标集合'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: groups.map((group) {
                  final active = group.id == groupId;
                  return GestureDetector(
                    onTap: () => setLocal(() {
                      groupId = group.id;
                      folderId = '';
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? const Color(0x1F38BDF8) : const Color(0x08FFFFFF),
                        border: Border.all(
                          color: active ? const Color(0x4038BDF8) : AstraColors.line,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        group.name,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: active ? AstraColors.accent : AstraColors.muted,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const SectionLabel('目标文件夹'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _folderChip(
                    label: '（集合根目录）',
                    active: folderId.isEmpty,
                    onTap: () => setLocal(() => folderId = ''),
                  ),
                  ...folders.map((folder) => _folderChip(
                        label: state.folderPath(folder.id),
                        active: folderId == folder.id,
                        onTap: () => setLocal(() => folderId = folder.id),
                      )),
                ],
              ),
            ],
          ),
          actions: [
            GhostButton(label: '取消', onPressed: () => Navigator.of(ctx).pop()),
            GradientButton(
              label: '移动',
              onPressed: () {
                state.moveEntry(entryId, groupId, folderId);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        );
      },
    ),
  );
}

Widget _folderChip({
  required String label,
  required bool active,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0x1F38BDF8) : const Color(0x08FFFFFF),
        border: Border.all(
          color: active ? const Color(0x4038BDF8) : AstraColors.line,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: active ? AstraColors.accent : AstraColors.muted,
        ),
      ),
    ),
  );
}

/* ------------------------------------------------------------------ */
/* 示例                                                                */
/* ------------------------------------------------------------------ */

Future<void> showExamplesDialog(
  BuildContext context,
  AppState state,
  String entryId,
) async {
  var selected = 0;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final entry =
            state.collections.where((item) => item.id == entryId).firstOrNull;
        final examples = entry?.examples ?? <RequestExample>[];
        if (selected >= examples.length) selected = 0;
        final example = examples.isEmpty ? null : examples[selected];
        String pretty = example?.body ?? '';
        try {
          pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(pretty));
        } catch (_) {}

        return AstraDialogShell(
          title: '响应示例 · ${entry?.name ?? ''}',
          subtitle: '示例保存在请求上，可用于回归对照或分享。',
          width: 860,
          child: SizedBox(
            height: 430,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 220,
                  child: examples.isEmpty
                      ? const Text(
                          '还没有示例\n在响应区点击「存为示例」即可保存',
                          style: TextStyle(fontSize: 11, color: AstraColors.faint, height: 1.7),
                        )
                      : ListView.builder(
                          itemCount: examples.length,
                          itemBuilder: (context, index) {
                            final item = examples[index];
                            final active = index == selected;
                            return InkWell(
                              onTap: () => setLocal(() => selected = index),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0x1638BDF8)
                                      : const Color(0x06FFFFFF),
                                  border: Border.all(
                                    color: active
                                        ? const Color(0x4038BDF8)
                                        : AstraColors.line,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${item.status} · ${_timeLabel(item.ts)}',
                                      style: const TextStyle(
                                        fontSize: 9.5,
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
                          if (example != null) ...[
                            Text(
                              'HTTP ${example.status}',
                              style: monoStyle(
                                size: 11,
                                color: statusColor(example.status),
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              formatBytes(utf8.encode(example.body).length),
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AstraColors.muted,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (example != null)
                            GhostButton(
                              label: '删除',
                              icon: Icons.delete_outline,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              onPressed: () {
                                state.deleteExample(entryId, example.id);
                                setLocal(() {});
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B0F17),
                            border: Border.all(color: AstraColors.line),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              pretty,
                              style: monoStyle(
                                size: 11.5,
                                height: 1.55,
                                color: const Color(0xFFD6DEF0),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            GradientButton(label: '关闭', onPressed: () => Navigator.of(ctx).pop()),
          ],
        );
      },
    ),
  );
}

String _timeLabel(int ms) {
  if (ms <= 0) return '';
  final time = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.month}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}

/* ------------------------------------------------------------------ */
/* 代理 / 客户端证书                                                   */
/* ------------------------------------------------------------------ */

Future<void> showNetworkSettingsDialog(BuildContext context, AppState state) async {
  final draft = state.settings.copy();
  final proxy = TextEditingController(text: draft.proxyUrl);
  final bypass = TextEditingController(text: draft.proxyBypass);
  final cert = TextEditingController(text: draft.certPath);
  final key = TextEditingController(text: draft.keyPath);
  final password = TextEditingController(text: draft.keyPassword);

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AstraDialogShell(
        title: '网络设置',
        subtitle: '代理与客户端证书对所有请求生效，也可用于企业内网抓包调试。',
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('HTTP / SOCKS 代理'),
              BoundTextField(
                value: proxy.text,
                hint: 'http://127.0.0.1:8080 或 socks5://127.0.0.1:1080',
                onChanged: (value) => proxy.text = value,
              ),
              const SizedBox(height: 8),
              BoundTextField(
                value: bypass.text,
                hint: '不代理的主机，逗号分隔，例如 localhost,*.internal.com',
                onChanged: (value) => bypass.text = value,
              ),
              const SizedBox(height: 18),
              const SectionLabel('mTLS 客户端证书'),
              BoundTextField(
                value: cert.text,
                hint: '客户端证书链路径（.pem / .crt）',
                onChanged: (value) => cert.text = value,
              ),
              const SizedBox(height: 8),
              BoundTextField(
                value: key.text,
                hint: '私钥路径（.pem / .key）',
                onChanged: (value) => key.text = value,
              ),
              const SizedBox(height: 8),
              BoundTextField(
                value: password.text,
                hint: '私钥密码（可留空）',
                obscure: true,
                onChanged: (value) => password.text = value,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('校验 TLS 证书', style: TextStyle(fontSize: 12.5)),
                        const SizedBox(height: 2),
                        const Text(
                          '关闭后接受自签名证书，仅建议在测试环境使用',
                          style: TextStyle(fontSize: 10.5, color: AstraColors.faint),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: draft.verifyTls,
                    activeThumbColor: AstraColors.accent,
                    onChanged: (value) => setLocal(() => draft.verifyTls = value),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          GhostButton(label: '取消', onPressed: () => Navigator.of(ctx).pop()),
          GradientButton(
            label: '保存',
            onPressed: () {
              draft
                ..proxyUrl = proxy.text.trim()
                ..proxyBypass = bypass.text.trim()
                ..certPath = cert.text.trim()
                ..keyPath = key.text.trim()
                ..keyPassword = password.text;
              state.updateSettings(draft);
              Navigator.of(ctx).pop();
              state.showToast('网络设置已保存');
            },
          ),
        ],
      ),
    ),
  );
}

/* ------------------------------------------------------------------ */
/* 快捷键                                                              */
/* ------------------------------------------------------------------ */

Future<void> showShortcutsDialog(BuildContext context) async {
  const items = [
    ['⌘ / Ctrl + Enter', '发送当前请求'],
    ['⌘ / Ctrl + S', '保存当前请求'],
    ['⌘ / Ctrl + T', '新建请求标签页'],
    ['⌘ / Ctrl + W', '关闭当前标签页'],
    ['⌘ / Ctrl + Shift + V', '打开变量面板'],
    ['⌘ / Ctrl + Shift + R', '打开集合运行器'],
    ['⌘ / Ctrl + K', '打开快捷键面板'],
  ];
  await showDialog<void>(
    context: context,
    builder: (ctx) => AstraDialogShell(
      title: '快捷键',
      subtitle: '在 macOS 上使用 ⌘，在 Windows 上使用 Ctrl。',
      width: 470,
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 210,
                  child: Text(
                    item[0],
                    style: monoStyle(size: 11.5, color: AstraColors.accent),
                  ),
                ),
                Expanded(
                  child: Text(
                    item[1],
                    style: const TextStyle(fontSize: 11.5, color: AstraColors.muted),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
      actions: [
        GradientButton(label: '知道了', onPressed: () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}

/* ------------------------------------------------------------------ */
/* 响应示例保存                                                        */
/* ------------------------------------------------------------------ */

Future<void> showSaveExampleDialog(
  BuildContext context,
  AppState state,
  String entryId,
) async {
  final result = state.response;
  if (result == null) {
    state.showToast('还没有可保存的响应');
    return;
  }
  final controller = TextEditingController(
    text: '${state.request.method} ${_shortUrl(state.request.url)} · ${result.status}',
  );
  await showDialog<void>(
    context: context,
    builder: (ctx) => AstraDialogShell(
      title: '存为响应示例',
      subtitle: '保存本次响应的状态码、响应头与正文，方便后续对照。',
      width: 480,
      child: BoundTextField(
        value: controller.text,
        hint: '示例名称',
        onChanged: (value) => controller.text = value,
      ),
      actions: [
        GhostButton(label: '取消', onPressed: () => Navigator.of(ctx).pop()),
        GradientButton(
          label: '保存',
          onPressed: () {
            state.addExample(
              entryId,
              RequestExample(
                name: controller.text.trim().isEmpty ? '示例' : controller.text.trim(),
                status: result.status,
                body: result.text ?? '',
                headers: result.headers.map(
                  (key, value) => MapEntry(key, value.map((e) => '$e').toList()),
                ),
              ),
            );
            Navigator.of(ctx).pop();
            state.showToast('已保存为示例');
          },
        ),
      ],
    ),
  );
}

String _shortUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  return uri.path.isEmpty ? uri.host : '${uri.host}${uri.path}';
}

/// 复制文本并提示，供各处菜单复用。
Future<void> copyWithToast(
  BuildContext context,
  AppState state,
  String text,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  state.showToast(message);
}

/* ------------------------------------------------------------------ */
/* 集合 / 文件夹 变量                                                  */
/* ------------------------------------------------------------------ */

Future<void> showScopeVariablesDialog(
  BuildContext context,
  AppState state, {
  required String title,
  required List<KV> rows,
  required ValueChanged<List<KV>> onSave,
}) async {
  final draft = rows.map((item) => item.copy()).toList();
  if (draft.isEmpty) draft.add(KV());

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        return AstraDialogShell(
          title: title,
          subtitle: '该作用域内的请求可直接用 {{变量名}} 引用；内层作用域会覆盖外层同名变量。',
          width: 640,
          child: SizedBox(
            height: 380,
            child: SingleChildScrollView(
              child: KVEditor(
                rows: draft,
                keyHint: '变量名',
                valueHint: '值（支持引用其他变量）',
                varNames: state.varNames,
                onChanged: () => setLocal(() {}),
                onAdd: () => setLocal(() => draft.add(KV())),
                onRemove: (index) => setLocal(() => draft.removeAt(index)),
              ),
            ),
          ),
          actions: [
            GhostButton(label: '取消', onPressed: () => Navigator.of(ctx).pop()),
            GradientButton(
              label: '保存',
              onPressed: () {
                draft.removeWhere((item) => item.k.trim().isEmpty);
                if (draft.isEmpty) draft.add(KV());
                onSave(draft);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        );
      },
    ),
  );
}

/* ------------------------------------------------------------------ */
/* 集合 / 文件夹 认证                                                  */
/* ------------------------------------------------------------------ */

Future<void> showScopeAuthDialog(
  BuildContext context, {
  required String title,
  required AuthConfig current,
  required ValueChanged<AuthConfig> onSave,
}) async {
  final draft = current.copy();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Widget field(String label, String value, ValueChanged<String> onChanged,
            {String? hint}) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(label),
                const SizedBox(height: 6),
                BoundTextField(
                  value: value,
                  hint: hint ?? label,
                  fontSize: 12,
                  onChanged: onChanged,
                ),
              ],
            ),
          );
        }

        final types = <String>[
          'inherit',
          'none',
          'bearer',
          'basic',
          'apikey',
          'oauth2',
        ];
        const labels = {
          'inherit': '继承上级',
          'none': '无认证',
          'bearer': 'Bearer Token',
          'basic': 'Basic Auth',
          'apikey': 'API Key',
          'oauth2': 'OAuth 2.0',
        };

        return AstraDialogShell(
          title: title,
          subtitle: '作用域认证会自动应用到下级文件夹与请求，可在请求层选择「继承上级」使用。',
          width: 560,
          child: StatefulBuilder(
            builder: (ctx, setInner) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel('认证类型'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: types.contains(draft.type) ? draft.type : 'inherit',
                  dropdownColor: AstraColors.surface2,
                  style: const TextStyle(fontSize: 12.5, color: AstraColors.text),
                  decoration: astraInput(),
                  items: types
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(labels[type]!),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setInner(() => draft.type = value);
                  },
                ),
                const SizedBox(height: 14),
                if (draft.type == 'bearer')
                  field('Token', draft.token, (value) => draft.token = value,
                      hint: '支持 {{变量}}'),
                if (draft.type == 'basic') ...[
                  field('用户名', draft.username, (value) => draft.username = value),
                  field('密码', draft.password, (value) => draft.password = value),
                ],
                if (draft.type == 'apikey') ...[
                  field('Key 名称', draft.apiKeyName,
                      (value) => draft.apiKeyName = value,
                      hint: '例如 X-Api-Key'),
                  field('Key 值', draft.apiKeyValue,
                      (value) => draft.apiKeyValue = value),
                  SectionLabel('携带位置'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _authChip('请求头', draft.apiKeyIn == 'header', () {
                        setInner(() => draft.apiKeyIn = 'header');
                      }),
                      const SizedBox(width: 8),
                      _authChip('查询参数', draft.apiKeyIn == 'query', () {
                        setInner(() => draft.apiKeyIn = 'query');
                      }),
                    ],
                  ),
                ],
                if (draft.type == 'oauth2')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'OAuth 2.0 建议在具体请求中配置并获取 Token，集合层会复用请求中的 Token。',
                      style: TextStyle(fontSize: 11, color: AstraColors.faint, height: 1.5),
                    ),
                  ),
                if (draft.type == 'inherit')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      '使用上级集合的认证配置；若上级也未配置则不加认证。',
                      style: TextStyle(fontSize: 11, color: AstraColors.faint, height: 1.5),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            GhostButton(label: '取消', onPressed: () => Navigator.of(ctx).pop()),
            GradientButton(
              label: '保存',
              onPressed: () {
                onSave(draft);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        );
      },
    ),
  );
}

Widget _authChip(String label, bool active, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0x1F38BDF8) : const Color(0x08FFFFFF),
        border: Border.all(
          color: active ? const Color(0x4038BDF8) : AstraColors.line,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: active ? AstraColors.accent : AstraColors.muted,
        ),
      ),
    ),
  );
}

/* ------------------------------------------------------------------ */
/* 定时监控                                                            */
/* ------------------------------------------------------------------ */

Future<void> showMonitorsDialog(
  BuildContext context,
  AppState state,
  CollectionGroup group,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AnimatedBuilder(
      animation: state,
      builder: (ctx, _) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final monitors = state.monitorsFor(group.id);
          return AstraDialogShell(
            title: '定时监控 · ${group.name}',
            subtitle: '按固定间隔自动运行集合，记录通过率；应用需保持运行。',
            width: 680,
            child: SizedBox(
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '${monitors.length} 个监控任务',
                        style: const TextStyle(fontSize: 11.5, color: AstraColors.muted),
                      ),
                      const Spacer(),
                      GradientButton(
                        label: '新建监控',
                        icon: Icons.add_alarm,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        onPressed: () {
                          state.addMonitor(
                            groupId: group.id,
                            name: '${group.name} 监控',
                            intervalMinutes: 30,
                          );
                          setLocal(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: monitors.isEmpty
                        ? const EmptyHint(
                            icon: Icons.monitor_heart_outlined,
                            title: '还没有定时监控',
                            subtitle: '新建后可按固定间隔自动运行集合，\n并在下方看到最近一次通过率',
                          )
                        : ListView.builder(
                            itemCount: monitors.length,
                            itemBuilder: (context, index) {
                              final monitor = monitors[index];
                              MonitorConfig patch({
                                String? name,
                                int? interval,
                                bool? enabled,
                              }) =>
                                  MonitorConfig(
                                    id: monitor.id,
                                    groupId: monitor.groupId,
                                    name: name ?? monitor.name,
                                    intervalMinutes:
                                        interval ?? monitor.intervalMinutes,
                                    iterations: monitor.iterations,
                                    enabled: enabled ?? monitor.enabled,
                                    lastRunAt: monitor.lastRunAt,
                                    lastPassed: monitor.lastPassed,
                                    lastTotal: monitor.lastTotal,
                                    lastError: monitor.lastError,
                                  );
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0x06FFFFFF),
                                  border: Border.all(color: AstraColors.line),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            monitor.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12, color: AstraColors.text),
                                          ),
                                        ),
                                        Switch(
                                          value: monitor.enabled,
                                          activeThumbColor: AstraColors.accent,
                                          onChanged: (value) {
                                            state.updateMonitor(
                                                patch(enabled: value));
                                            setLocal(() {});
                                          },
                                        ),
                                        IconButton(
                                          tooltip: '立即运行',
                                          iconSize: 16,
                                          color: AstraColors.muted,
                                          onPressed: () async {
                                            await state.runMonitorNow(monitor);
                                            setLocal(() {});
                                          },
                                          icon: const Icon(Icons.play_arrow_rounded),
                                        ),
                                        IconButton(
                                          tooltip: '删除',
                                          iconSize: 15,
                                          color: AstraColors.faint,
                                          onPressed: () {
                                            state.deleteMonitor(monitor.id);
                                            setLocal(() {});
                                          },
                                          icon: const Icon(Icons.delete_outline),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Text('间隔',
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                color: AstraColors.faint)),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 70,
                                          child: BoundTextField(
                                            value: monitor.intervalMinutes.toString(),
                                            fontSize: 11,
                                            onChanged: (value) {
                                              final parsed = int.tryParse(value.trim());
                                              if (parsed == null || parsed <= 0) return;
                                              state.updateMonitor(
                                                  patch(interval: parsed));
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text('分钟',
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                color: AstraColors.faint)),
                                        const Spacer(),
                                        Text(
                                          monitor.lastTotal == 0
                                              ? '尚未运行'
                                              : '最近 ${monitor.lastPassed}/${monitor.lastTotal} 通过',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: monitor.lastTotal > 0 &&
                                                    monitor.lastPassed ==
                                                        monitor.lastTotal
                                                ? AstraColors.ok
                                                : AstraColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (monitor.lastError.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          monitor.lastError,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 10, color: AstraColors.err),
                                        ),
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
            actions: [
              GhostButton(label: '关闭', onPressed: () => Navigator.of(ctx).pop()),
            ],
          );
        },
      ),
    ),
  );
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/env_vars.dart';
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
            'Global',
            'Base variables available to all requests',
            state.globals,
            (rows) => state.setGlobals(rows),
            false,
          ),
          for (final group in state.groups)
            _VarScope(
              'Collection · ${group.name}',
              'Available to requests in this collection only',
              group.variables,
              (rows) => state.setCollectionVariables(group.id, rows),
              false,
            ),
          for (final folder in state.folders)
            _VarScope(
              'Folder · ${state.folderPath(folder.id)}',
              'Available to this folder and its subfolders; overrides collection variables',
              folder.variables,
              (rows) => state.setFolderVariables(folder.id, rows),
              false,
            ),
          _VarScope(
            'Environment · ${state.env.name}',
            'Active environment; takes precedence over collection and folder variables',
            state.env.vars,
            null,
            true,
          ),
          _VarScope(
            'Runtime',
            'Set by scripts via pm.variables.set; valid for the current session only',
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
          title: 'Variables',
          subtitle: 'Precedence from low to high: Global → Collection → Folder → '
              'Environment → Request → Runtime. Typing {{ in an input field '
              'autocompletes variable names.',
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
                            margin: EdgeInsets.only(bottom: 6),
                            padding: EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                            decoration: BoxDecoration(
                              color: active ? AstraColors.accentSoft : AstraColors.overlay,
                              border: Border.all(
                                color: active ? AstraColors.accentBorder : AstraColors.line,
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
                                      SizedBox(height: 2),
                                      Text(
                                        scopes[i].description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: AstraColors.faint,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '$count',
                                  style: TextStyle(
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
                SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              current.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (current.readOnly)
                            Text(
                              'Read-only',
                              style: TextStyle(
                                fontSize: 10,
                                color: AstraColors.faint,
                              ),
                            ),
                          if (current.label.startsWith('Environment')) ...[
                            SizedBox(width: 10),
                            GhostButton(
                              label: 'Manage Environments',
                              icon: Icons.tune,
                              padding:
                                  EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              onPressed: () => showEnvManagerDialog(ctx, state),
                            ),
                          ],
                          if (!current.readOnly) ...[
                            SizedBox(width: 8),
                            GhostButton(
                              label: 'Import .env / CSV',
                              icon: Icons.upload_file,
                              padding:
                                  EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              onPressed: () async {
                                final rows = await showVariableImportDialog(ctx);
                                if (rows == null || rows.isEmpty) return;
                                setLocal(() {
                                  _mergeVariableRows(current.rows, rows);
                                });
                                if (current.onChanged != null) {
                                  current.onChanged!(current.rows);
                                } else if (current.label.startsWith('Environment')) {
                                  state.setActiveEnvVars(current.rows);
                                }
                                state.showToast('Imported ${rows.length} variable(s)');
                              },
                            ),
                            SizedBox(width: 8),
                            GhostButton(
                              label: 'Copy .env',
                              icon: Icons.copy_all,
                              padding:
                                  EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              onPressed: () async {
                                final text = toDotEnv(current.rows);
                                await Clipboard.setData(ClipboardData(text: text));
                                state.showToast('Copied .env to clipboard');
                              },
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: current.readOnly
                              ? _ReadonlyVars(rows: current.rows, merged: merged)
                              : KVEditor(
                                  rows: current.rows,
                                  keyHint: 'Variable name',
                                  valueHint: 'Value',
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
              '${state.varNames.length} variables available',
              style: TextStyle(fontSize: 10.5, color: AstraColors.faint),
            ),
            Spacer(),
            GradientButton(
              label: 'Done',
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

  _ReadonlyVars({required this.rows, required this.merged});

  @override
  Widget build(BuildContext context) {
    final items = rows.where((row) => row.k.trim().isNotEmpty).toList();
    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Text(
          'No variables at this level yet',
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
          margin: EdgeInsets.only(bottom: 6),
          padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: AstraColors.overlay,
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
                  'Overridden by ${effective ?? ''}',
                  style: TextStyle(fontSize: 9.5, color: AstraColors.warn),
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
      title: 'Final Request Preview',
      subtitle: 'Resolved with the current variable scopes for review before sending.',
      width: 720,
      child: SizedBox(
        height: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (unresolved.isNotEmpty)
                Container(
                  margin: EdgeInsets.only(bottom: 12),
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AstraColors.warnSoft,
                    border: Border.all(color: AstraColors.warnSoft),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Unresolved variables: ${unresolved.join(', ')}',
                    style: TextStyle(fontSize: 10.8, color: AstraColors.warn),
                  ),
                ),
              _previewBlock('${req.method} $url'),
              SizedBox(height: 12),
              SectionLabel('Headers'),
              _previewBlock(
                headers.isEmpty
                    ? '(empty)'
                    : headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
              ),
              SizedBox(height: 12),
              SectionLabel('Body'),
              _previewBlock(body.isEmpty ? '(empty)' : body),
            ],
          ),
        ),
      ),
      actions: [
        GhostButton(
          label: 'Edit Variables',
          icon: Icons.data_object,
          onPressed: () => showVariablesDialog(ctx, state),
        ),
        GradientButton(
          label: 'Close',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
}

Widget _previewBlock(String text) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: AstraColors.inset,
      border: Border.all(color: AstraColors.line),
      borderRadius: BorderRadius.circular(9),
    ),
    child: SelectableText(
      text,
      style: monoStyle(size: 11.5, height: 1.55, color: AstraColors.codeText),
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
        .where((row) => row.k.trim().isNotEmpty || row.v.trim().isNotEmpty)
        .map((row) => '${row.on ? '' : '// '}${row.k}: ${row.v}')
        .join('\n'),
  );

  await showDialog<void>(
    context: context,
    builder: (ctx) => AstraDialogShell(
      title: title,
      subtitle:
          'One entry per line as key: value. Prefix a line with // to disable it.',
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
            contentPadding: EdgeInsets.all(12),
          ),
        ),
      ),
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        GradientButton(
          label: 'Apply',
          onPressed: () {
            final parsed = <KV>[];
            for (final line in controller.text.split('\n')) {
              var trimmed = line.trim();
              if (trimmed.isEmpty) continue;
              var on = true;
              if (trimmed.startsWith('//')) {
                on = false;
                trimmed = trimmed.substring(2).trim();
                if (trimmed.isEmpty) continue;
              }
              final index = trimmed.indexOf(':');
              if (index <= 0) {
                parsed.add(KV(on: on, k: trimmed, v: ''));
              } else {
                parsed.add(KV(
                  on: on,
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
      subtitle: '$beforeLabel → $afterLabel · $added lines added, $removed lines removed',
      width: 900,
      child: SizedBox(
        height: 460,
        child: Container(
          decoration: BoxDecoration(
            color: AstraColors.inset,
            border: Border.all(color: AstraColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final color = switch (row.type) {
                1 => AstraColors.okContainer,
                -1 => AstraColors.errContainer,
                _ => Colors.transparent,
              };
              final marker = switch (row.type) {
                1 => '+',
                -1 => '-',
                _ => ' ',
              };
              return Container(
                color: color,
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
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
                    SizedBox(width: 8),
                    Text(
                      marker,
                      style: monoStyle(
                        size: 11.5,
                        color: row.type == 0 ? AstraColors.faint : AstraColors.text,
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        row.text.isEmpty ? ' ' : row.text,
                        style: monoStyle(
                          size: 11.5,
                          height: 1.5,
                          color: AstraColors.codeText,
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
        GradientButton(label: 'Close', onPressed: () => Navigator.of(ctx).pop()),
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
      title: 'Request Info',
      subtitle: 'The name appears in tabs and the sidebar; the description appears '
          'in the sidebar tooltip.',
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BoundTextField(
            value: name.text,
            hint: 'Request name',
            onChanged: (value) => name.text = value,
          ),
          SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: TextField(
              controller: description,
              expands: true,
              maxLines: null,
              minLines: null,
              style: TextStyle(fontSize: 12, height: 1.55),
              decoration: astraInput(
                hint: 'Purpose, dependencies, notes…',
                contentPadding: EdgeInsets.all(11),
              ),
            ),
          ),
        ],
      ),
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
        GradientButton(
          label: 'Save',
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
          title: 'Move to…',
          subtitle: 'Choose the target collection and folder. The request moves to '
              'the group of the selected collection.',
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel('Target Collection'),
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
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? AstraColors.accentSoft : AstraColors.overlay,
                        border: Border.all(
                          color: active ? AstraColors.accentBorder : AstraColors.line,
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
              SizedBox(height: 16),
              SectionLabel('Target Folder'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _folderChip(
                    label: '(Collection Root)',
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
            GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
            GradientButton(
              label: 'Move',
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
      padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: active ? AstraColors.accentSoft : AstraColors.overlay,
        border: Border.all(
          color: active ? AstraColors.accentBorder : AstraColors.line,
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
          title: 'Response Examples · ${entry?.name ?? ''}',
          subtitle: 'Examples are saved with the request and can be used for '
              'regression checks or sharing.',
          width: 860,
          child: SizedBox(
            height: 430,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 220,
                  child: examples.isEmpty
                      ? Text(
                          'No examples yet\nClick "Save as Example" in the Response area to save one',
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
                                margin: EdgeInsets.only(bottom: 6),
                                padding:
                                    EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                                decoration: BoxDecoration(
                                  color: active
                                      ? AstraColors.accentSoft
                                      : AstraColors.overlay,
                                  border: Border.all(
                                    color: active
                                        ? AstraColors.accentBorder
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
                                      style: TextStyle(fontSize: 11.5),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      '${item.status} · ${_timeLabel(item.ts)}',
                                      style: TextStyle(
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
                SizedBox(width: 16),
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
                            SizedBox(width: 10),
                            Text(
                              formatBytes(utf8.encode(example.body).length),
                              style: TextStyle(
                                fontSize: 10.5,
                                color: AstraColors.muted,
                              ),
                            ),
                          ],
                          Spacer(),
                          if (example != null)
                            GhostButton(
                              label: 'Delete',
                              icon: Icons.delete_outline,
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              onPressed: () {
                                state.deleteExample(entryId, example.id);
                                setLocal(() {});
                              },
                            ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: AstraColors.inset,
                            border: Border.all(color: AstraColors.line),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              pretty,
                              style: monoStyle(
                                size: 11.5,
                                height: 1.55,
                                color: AstraColors.codeText,
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
            GradientButton(label: 'Close', onPressed: () => Navigator.of(ctx).pop()),
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
        title: 'Network Settings',
        subtitle: 'The proxy and client certificate apply to all requests; useful for '
            'debugging traffic on corporate networks.',
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel('HTTP / SOCKS Proxy'),
              BoundTextField(
                value: proxy.text,
                hint: 'http://127.0.0.1:8080 or socks5://127.0.0.1:1080',
                onChanged: (value) => proxy.text = value,
              ),
              SizedBox(height: 8),
              BoundTextField(
                value: bypass.text,
                hint: 'Hosts to bypass, comma-separated, e.g. localhost,*.internal.com',
                onChanged: (value) => bypass.text = value,
              ),
              SizedBox(height: 18),
              SectionLabel('mTLS Client Certificate'),
              BoundTextField(
                value: cert.text,
                hint: 'Client certificate chain path (.pem / .crt)',
                onChanged: (value) => cert.text = value,
              ),
              SizedBox(height: 8),
              BoundTextField(
                value: key.text,
                hint: 'Private key path (.pem / .key)',
                onChanged: (value) => key.text = value,
              ),
              SizedBox(height: 8),
              BoundTextField(
                value: password.text,
                hint: 'Private key password (optional)',
                obscure: true,
                onChanged: (value) => password.text = value,
              ),
              SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Verify TLS certificate', style: TextStyle(fontSize: 12.5)),
                        SizedBox(height: 2),
                        Text(
                          'When off, self-signed certificates are accepted. Use only in test environments',
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
          GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
          GradientButton(
            label: 'Save',
            onPressed: () {
              draft
                ..proxyUrl = proxy.text.trim()
                ..proxyBypass = bypass.text.trim()
                ..certPath = cert.text.trim()
                ..keyPath = key.text.trim()
                ..keyPassword = password.text;
              state.updateSettings(draft);
              Navigator.of(ctx).pop();
              state.showToast('Network settings saved');
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
    ['⌘ / Ctrl + Enter', 'Send current request'],
    ['⌘ / Ctrl + S', 'Save current request'],
    ['⌘ / Ctrl + N', 'New request tab'],
    ['⌘ / Ctrl + T', 'New request tab'],
    ['⌘ / Ctrl + W', 'Close current tab'],
    ['⌥ + ← / →', 'Previous / next tab'],
    ['⌘ / Ctrl + Shift + V', 'Open Variables panel'],
    ['⌘ / Ctrl + Shift + R', 'Open Collection Runner'],
    ['⌘ / Ctrl + K', 'Open Keyboard Shortcuts'],
    ['F2', 'Rename selected collection, folder or request'],
    ['⌘ / Ctrl + D', 'Duplicate selection'],
    ['Delete / ⌫', 'Delete selection'],
    ['⌥ + ⌘ / Ctrl + R', 'New request in selection'],
    ['⌥ + ⌘ / Ctrl + F', 'New folder in selection'],
    ['⌥ + ⌘ / Ctrl + C', 'New collection'],
    ['⌘ / Ctrl + Shift + Enter', 'Run selected collection or folder'],
  ];
  await showDialog<void>(
    context: context,
    builder: (ctx) => AstraDialogShell(
      title: 'Keyboard Shortcuts',
      subtitle: 'Use ⌘ on macOS and Ctrl on Windows.',
      width: 470,
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: EdgeInsets.only(bottom: 9),
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
                    style: TextStyle(fontSize: 11.5, color: AstraColors.muted),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
      actions: [
        GradientButton(label: 'Got it', onPressed: () => Navigator.of(ctx).pop()),
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
    state.showToast('No response to save yet');
    return;
  }
  final controller = TextEditingController(
    text: '${state.request.method} ${_shortUrl(state.request.url)} · ${result.status}',
  );
  await showDialog<void>(
    context: context,
    builder: (ctx) => AstraDialogShell(
      title: 'Save as Response Example',
      subtitle: 'Save the status code, response headers and body of this response '
          'for later comparison.',
      width: 480,
      child: BoundTextField(
        value: controller.text,
        hint: 'Example name',
        onChanged: (value) => controller.text = value,
      ),
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
        GradientButton(
          label: 'Save',
          onPressed: () {
            state.addExample(
              entryId,
              RequestExample(
                name: controller.text.trim().isEmpty ? 'Example' : controller.text.trim(),
                status: result.status,
                body: result.text ?? '',
                headers: result.headers.map(
                  (key, value) => MapEntry(key, value.map((e) => '$e').toList()),
                ),
              ),
            );
            Navigator.of(ctx).pop();
            state.showToast('Saved as example');
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
          subtitle: 'Requests in this scope can reference values with {{variable}}; '
              'inner scopes override outer ones with the same name.',
          width: 640,
          child: SizedBox(
            height: 380,
            child: SingleChildScrollView(
              child: KVEditor(
                rows: draft,
                keyHint: 'Variable name',
                valueHint: 'Value (may reference other variables)',
                varNames: state.varNames,
                onChanged: () => setLocal(() {}),
                onAdd: () => setLocal(() => draft.add(KV())),
                onRemove: (index) => setLocal(() => draft.removeAt(index)),
              ),
            ),
          ),
          actions: [
            GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
            GradientButton(
              label: 'Save',
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
            padding: EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(label),
                SizedBox(height: 6),
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
          'inherit': 'Inherit from parent',
          'none': 'No Auth',
          'bearer': 'Bearer Token',
          'basic': 'Basic Auth',
          'apikey': 'API Key',
          'oauth2': 'OAuth 2.0',
        };

        return AstraDialogShell(
          title: title,
          subtitle: 'Scope authorization applies automatically to subfolders and requests; '
              'choose "Inherit from parent" at the request level to use it.',
          width: 560,
          child: StatefulBuilder(
            builder: (ctx, setInner) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel('Auth Type'),
                SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: types.contains(draft.type) ? draft.type : 'inherit',
                  dropdownColor: AstraColors.surface2,
                  style: TextStyle(fontSize: 12.5, color: AstraColors.text),
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
                SizedBox(height: 14),
                if (draft.type == 'bearer')
                  field('Token', draft.token, (value) => draft.token = value,
                      hint: 'Supports {{variable}}'),
                if (draft.type == 'basic') ...[
                  field('Username', draft.username, (value) => draft.username = value),
                  field('Password', draft.password, (value) => draft.password = value),
                ],
                if (draft.type == 'apikey') ...[
                  field('Key name', draft.apiKeyName,
                      (value) => draft.apiKeyName = value,
                      hint: 'e.g. X-Api-Key'),
                  field('Key value', draft.apiKeyValue,
                      (value) => draft.apiKeyValue = value),
                  SectionLabel('Add To'),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      _authChip('Header', draft.apiKeyIn == 'header', () {
                        setInner(() => draft.apiKeyIn = 'header');
                      }),
                      SizedBox(width: 8),
                      _authChip('Query Params', draft.apiKeyIn == 'query', () {
                        setInner(() => draft.apiKeyIn = 'query');
                      }),
                    ],
                  ),
                ],
                if (draft.type == 'oauth2')
                  Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Configure OAuth 2.0 and obtain tokens on individual requests; '
                      'the collection reuses the request token.',
                      style: TextStyle(fontSize: 11, color: AstraColors.faint, height: 1.5),
                    ),
                  ),
                if (draft.type == 'inherit')
                  Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Uses the parent collection authorization settings; if the parent '
                      'has none, no auth is applied.',
                      style: TextStyle(fontSize: 11, color: AstraColors.faint, height: 1.5),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
            GradientButton(
              label: 'Save',
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
      padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: active ? AstraColors.accentSoft : AstraColors.overlay,
        border: Border.all(
          color: active ? AstraColors.accentBorder : AstraColors.line,
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
            title: 'Monitors · ${group.name}',
            subtitle: 'Run the collection automatically at a fixed interval and track '
                'pass rate; the app must stay open.',
            width: 680,
            child: SizedBox(
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '${monitors.length} monitors',
                        style: TextStyle(fontSize: 11.5, color: AstraColors.muted),
                      ),
                      Spacer(),
                      GradientButton(
                        label: 'New Monitor',
                        icon: Icons.add_alarm,
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        onPressed: () {
                          state.addMonitor(
                            groupId: group.id,
                            name: '${group.name} Monitor',
                            intervalMinutes: 30,
                          );
                          setLocal(() {});
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Expanded(
                    child: monitors.isEmpty
                        ? EmptyHint(
                            icon: Icons.monitor_heart_outlined,
                            title: 'No monitors yet',
                            subtitle: 'Create one to run this collection at a fixed interval,\n'
                                'and see the latest pass rate below',
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
                                margin: EdgeInsets.only(bottom: 8),
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AstraColors.overlay,
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
                                            style: TextStyle(
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
                                          tooltip: 'Run now',
                                          iconSize: 16,
                                          color: AstraColors.muted,
                                          onPressed: () async {
                                            await state.runMonitorNow(monitor);
                                            setLocal(() {});
                                          },
                                          icon: Icon(Icons.play_arrow_rounded),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete',
                                          iconSize: 15,
                                          color: AstraColors.faint,
                                          onPressed: () {
                                            state.deleteMonitor(monitor.id);
                                            setLocal(() {});
                                          },
                                          icon: Icon(Icons.delete_outline),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text('Interval',
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                color: AstraColors.faint)),
                                        SizedBox(width: 8),
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
                                        SizedBox(width: 6),
                                        Text('min',
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                color: AstraColors.faint)),
                                        Spacer(),
                                        Text(
                                          monitor.lastTotal == 0
                                              ? 'Not run yet'
                                              : 'Last ${monitor.lastPassed}/${monitor.lastTotal} passed',
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
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text(
                                          monitor.lastError,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
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
              GhostButton(label: 'Close', onPressed: () => Navigator.of(ctx).pop()),
            ],
          );
        },
      ),
    ),
  );
}

/// 导入时按变量名合并：已存在的变量更新值，新变量追加到末尾。
void _mergeVariableRows(List<KV> target, List<KV> incoming) {
  for (final row in incoming) {
    final key = row.k.trim();
    if (key.isEmpty) continue;
    final index = target.indexWhere((item) => item.k.trim() == key);
    if (index >= 0) {
      target[index]
        ..v = row.v
        ..on = true;
    } else {
      target.add(row);
    }
  }
}

/// 粘贴 `.env` 或 CSV 文本，解析为变量行；取消时返回 null。
Future<List<KV>?> showVariableImportDialog(BuildContext context) async {
  final controller = TextEditingController();
  String? error;
  final parsed = await showDialog<List<KV>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AstraDialogShell(
        title: 'Import variables',
        subtitle: 'Paste a .env file (KEY=VALUE per line) or CSV rows (key,value). '
            'Lines starting with # are ignored; existing variables are updated.',
        width: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              minLines: 8,
              maxLines: 14,
              autofocus: true,
              style: monoStyle(size: 11.5, height: 1.5),
              decoration: astraInput(
                hint: 'BASE_URL=https://api.example.com\nAPI_TOKEN="abc 123"\n\n# or CSV\nkey,value\nBASE_URL,https://api.example.com',
                contentPadding: const EdgeInsets.all(11),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: TextStyle(fontSize: 11.5, color: AstraColors.err)),
            ],
          ],
        ),
        actions: [
          GhostButton(
            label: 'Cancel',
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          const SizedBox(width: 8),
          GradientButton(
            label: 'Import',
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            onPressed: () {
              final rows = parseVariableText(controller.text);
              if (rows.isEmpty) {
                setLocal(() => error = 'No KEY=VALUE or CSV rows found');
                return;
              }
              Navigator.of(ctx).pop(rows);
            },
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return parsed;
}

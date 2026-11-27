import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import 'theme.dart';
import 'widgets.dart';

Widget _shell({
  required String title,
  String? subtitle,
  required Widget child,
  required List<Widget> actions,
  double width = 580,
}) {
  return Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: EdgeInsets.all(32),
    child: Container(
      width: width,
      constraints: BoxConstraints(maxHeight: 660),
      padding: EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: AstraColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AstraColors.line),
        boxShadow: [
          BoxShadow(color: Color(0x8C000000), blurRadius: 60, offset: Offset(0, 24)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            SizedBox(height: 5),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11.5, color: AstraColors.muted, height: 1.6),
            ),
          ],
          SizedBox(height: 16),
          Flexible(child: child),
          SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions,
          ),
        ],
      ),
    ),
  );
}

/* ------------------------------------------------------------------ */
/* 环境变量                                                            */
/* ------------------------------------------------------------------ */

Future<void> showEnvManagerDialog(BuildContext context, AppState state) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => _shell(
        title: 'Environment Manager',
        subtitle: 'Keep separate variable sets for Development / Staging / Production. '
            'Use {{variable}} in requests to reference the active environment.',
        width: 700,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final env in state.environments)
                      _EnvRow(
                        env: env,
                        active: env.id == state.activeEnvId,
                        onSwitch: () {
                          state.switchEnv(env.id);
                          setLocal(() {});
                        },
                        onEdit: () async {
                          await showEnvDialog(ctx, state, envId: env.id);
                          setLocal(() {});
                        },
                        onDuplicate: () {
                          state.duplicateEnv(env.id);
                          setLocal(() {});
                        },
                        onDelete: () async {
                          final ok = await showConfirmDialog(
                            ctx,
                            title: 'Delete Environment',
                            message: 'Delete environment "${env.name}" and its variables? '
                                'This cannot be undone.',
                          );
                          if (!ok) return;
                          if (!state.deleteEnv(env.id)) {
                            state.showToast('At least one environment is required');
                          }
                          setLocal(() {});
                        },
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                label: 'New Environment',
                icon: Icons.add,
                onPressed: () async {
                  await showEnvDialog(ctx, state);
                  setLocal(() {});
                },
              ),
            ),
          ],
        ),
        actions: [
          GradientButton(
            label: 'Done',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    ),
  );
}

class _EnvRow extends StatelessWidget {
  final Env env;
  final bool active;
  final VoidCallback onSwitch;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  _EnvRow({
    required this.env,
    required this.active,
    required this.onSwitch,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final count = env.vars.where((item) => item.k.trim().isNotEmpty).length;
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: active ? AstraColors.accentSoft : AstraColors.overlay,
        border: Border.all(
          color: active ? AstraColors.accentBorder : AstraColors.line,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 15,
            color: active ? AstraColors.accent : AstraColors.faint,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        env.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: AstraColors.text),
                      ),
                    ),
                    if (active) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AstraColors.accentSoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Active',
                          style: TextStyle(fontSize: 9, color: AstraColors.accent),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  '$count variables',
                  style: TextStyle(fontSize: 10, color: AstraColors.faint),
                ),
              ],
            ),
          ),
          if (!active)
            TextButton(
              onPressed: onSwitch,
              style: TextButton.styleFrom(
                foregroundColor: AstraColors.accent,
                textStyle: TextStyle(fontSize: 11),
              ),
              child: Text('Switch'),
            ),
          IconButton(
            tooltip: 'Edit variables',
            onPressed: onEdit,
            iconSize: 15,
            color: AstraColors.muted,
            icon: Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Duplicate environment',
            onPressed: onDuplicate,
            iconSize: 15,
            color: AstraColors.muted,
            icon: Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Delete environment',
            onPressed: onDelete,
            iconSize: 15,
            color: AstraColors.faint,
            icon: Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

Future<void> showEnvDialog(BuildContext context, AppState state, {String? envId}) async {
  final existing = envId == null
      ? null
      : state.environments.where((item) => item.id == envId).firstOrNull;
  final nameController = TextEditingController(text: existing?.name ?? 'New Environment');
  final vars = (existing?.vars ?? [KV()]).map((item) => item.copy()).toList();
  if (vars.isEmpty) vars.add(KV());

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => _shell(
        title: existing == null ? 'New Environment' : 'Edit Environment',
        subtitle: 'Reference values with {{variable}} in requests; they are resolved '
            'to the active environment before sending.',
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(fontSize: 12.5),
                decoration: astraInput(hint: 'Environment name, e.g. Development / Staging / Production'),
              ),
              SizedBox(height: 16),
              KVEditor(
                rows: vars,
                onChanged: () {},
                keyHint: 'Variable name',
                valueHint: 'Value',
                onAdd: () => setLocal(() => vars.add(KV())),
                onRemove: (index) => setLocal(() => vars.removeAt(index)),
              ),
            ],
          ),
        ),
        actions: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          SizedBox(width: 10),
          GradientButton(
            label: 'Save',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    ),
  );

  if (result == true) {
    final cleaned = vars
        .where((item) => item.k.trim().isNotEmpty)
        .map((item) => KV(on: item.on, k: item.k.trim(), v: item.v))
        .toList();
    final name = nameController.text.trim().isEmpty ? 'Environment' : nameController.text.trim();
    final targetId = existing?.id ?? state.createEnv(name).id;
    state.updateEnvById(targetId, name, cleaned.isEmpty ? [KV()] : cleaned);
    state.showToast('Environment "$name" saved');
  }
  nameController.dispose();
}

/* ------------------------------------------------------------------ */
/* Cookie                                                              */
/* ------------------------------------------------------------------ */

Future<void> showCookieDialog(BuildContext context, AppState state) async {
  await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => _shell(
        title: 'Cookie Manager',
        subtitle: 'Set-Cookie response headers are stored automatically and sent back '
            'when the domain and path match.',
        width: 780,
        child: state.cookies.isEmpty
            ? Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: EmptyHint(
                  icon: Icons.cookie_outlined,
                  title: 'No cookies yet',
                  subtitle: 'Cookies appear here after sending a request that returns Set-Cookie',
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 6, right: 6),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: _Th('Name')),
                          Expanded(flex: 3, child: _Th('Value')),
                          Expanded(flex: 2, child: _Th('Domain')),
                          Expanded(flex: 2, child: _Th('Path')),
                          Expanded(flex: 2, child: _Th('Expires')),
                          SizedBox(width: 36),
                        ],
                      ),
                    ),
                    ...List.generate(state.cookies.length, (index) {
                      final cookie = state.cookies[index];
                      return Container(
                        padding: EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: AstraColors.line)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                cookie.name,
                                style: monoStyle(size: 11.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                cookie.value,
                                style: monoStyle(size: 11.5, color: AstraColors.muted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                cookie.domain,
                                style: monoStyle(size: 11, color: AstraColors.muted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                cookie.path,
                                style: monoStyle(size: 11, color: AstraColors.muted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                cookie.expires == 0
                                    ? 'Session'
                                    : DateTime.fromMillisecondsSinceEpoch(cookie.expires)
                                        .toString()
                                        .substring(0, 16),
                                style: monoStyle(size: 10.5, color: AstraColors.faint),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: IconButton(
                                tooltip: 'Delete',
                                onPressed: () {
                                  state.deleteCookie(index);
                                  setLocal(() {});
                                },
                                icon: Icon(Icons.close, size: 15),
                                color: AstraColors.faint,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
        actions: [
          GhostButton(
            label: 'Clear All',
            onPressed: state.cookies.isEmpty
                ? null
                : () {
                    state.clearCookies();
                    setLocal(() {});
                  },
          ),
          SizedBox(width: 10),
          GradientButton(
            label: 'Done',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    ),
  );
}

class _Th extends StatelessWidget {
  final String text;
  _Th(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 10, color: AstraColors.faint, letterSpacing: 0.6),
      );
}

/* ------------------------------------------------------------------ */
/* 保存请求                                                            */
/* ------------------------------------------------------------------ */

class SaveRequestResult {
  final String name;
  final String groupId;
  final String folderId;

  SaveRequestResult(this.name, this.groupId, this.folderId);
}

Future<SaveRequestResult?> showSaveDialog(BuildContext context, AppState state) async {
  CollectionEntry? existing;
  for (final entry in state.collections) {
    if (entry.id == state.selectedId) {
      existing = entry;
      break;
    }
  }
  final fallback = existing?.name ??
      (state.mode == 'ws'
          ? (state.ws.url.isEmpty ? 'Untitled WebSocket' : state.ws.url)
          : (state.request.url.isEmpty ? 'Untitled Request' : state.request.url));
  final controller = TextEditingController(text: fallback);
  var groupId = existing?.groupId ?? state.pendingGroupId;
  var folderId = existing?.folderId ?? state.pendingFolderId;

  final result = await showDialog<SaveRequestResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final options = state.groupsFor(state.mode);
        if (groupId.isNotEmpty && !options.any((item) => item.id == groupId)) {
          groupId = '';
        }
        if (groupId.isEmpty) folderId = '';
        final folderOptions =
            state.folders.where((folder) => folder.groupId == groupId).toList();
        if (folderId.isNotEmpty && !folderOptions.any((item) => item.id == folderId)) {
          folderId = '';
        }
        return _shell(
          title: existing == null ? 'Save to Collection' : 'Update Request in Collection',
          subtitle: state.mode == 'ws'
              ? 'WebSocket connections are organized by collection / folder and can be '
                  'loaded from the sidebar anytime.'
              : 'Choose the collection and folder for this request to keep things organized.',
          width: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(fontSize: 12.5),
                decoration: astraInput(hint: 'Name'),
                onSubmitted: (value) =>
                    Navigator.of(ctx).pop(SaveRequestResult(value, groupId, folderId)),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _selectBox(
                      value: groupId,
                      hint: 'Ungrouped',
                      items: [
                        DropdownMenuItem(value: '', child: Text('Ungrouped')),
                        ...options.map(
                          (group) => DropdownMenuItem(
                            value: group.id,
                            child: Text(group.name, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) => setLocal(() {
                        groupId = value ?? '';
                        folderId = '';
                      }),
                    ),
                  ),
                  SizedBox(width: 8),
                  GhostButton(
                    label: 'New Collection',
                    icon: Icons.create_new_folder_outlined,
                    onPressed: () async {
                      final name = await showGroupDialog(
                        ctx,
                        title: 'New Collection',
                        initial: '',
                        mode: state.mode,
                      );
                      if (name == null) return;
                      final created = state.createGroup(name, state.mode);
                      setLocal(() {
                        groupId = created.id;
                        folderId = '';
                      });
                    },
                  ),
                ],
              ),
              if (groupId.isNotEmpty) ...[
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _selectBox(
                        value: folderId,
                        hint: 'Collection root',
                        items: [
                          DropdownMenuItem(value: '', child: Text('Collection root')),
                          ...folderOptions.map(
                            (folder) => DropdownMenuItem(
                              value: folder.id,
                              child: Text(
                                state.folderPath(folder.id),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setLocal(() => folderId = value ?? ''),
                      ),
                    ),
                    SizedBox(width: 8),
                    GhostButton(
                      label: 'New Folder',
                      icon: Icons.create_new_folder_outlined,
                      onPressed: () async {
                        final name = await showGroupDialog(
                          ctx,
                          title: 'New Folder',
                          initial: '',
                          mode: state.mode,
                        );
                        if (name == null) return;
                        final created = state.createFolder(groupId, folderId, name);
                        setLocal(() => folderId = created.id);
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
            SizedBox(width: 10),
            GradientButton(
              label: 'Save',
              onPressed: () => Navigator.of(ctx).pop(
                SaveRequestResult(controller.text, groupId, folderId),
              ),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  return result;
}

Widget _selectBox({
  required String value,
  required String hint,
  required List<DropdownMenuItem<String>> items,
  required ValueChanged<String?> onChanged,
}) {
  return Container(
    height: 40,
    padding: EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: AstraColors.inset,
      border: Border.all(color: AstraColors.line),
      borderRadius: BorderRadius.circular(9),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        dropdownColor: AstraColors.surface2,
        style: TextStyle(fontSize: 12, color: AstraColors.text),
        hint: Text(
          hint,
          style: TextStyle(fontSize: 12, color: AstraColors.faint),
        ),
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}

Future<String?> showGroupDialog(
  BuildContext context, {
  required String title,
  required String initial,
  required String mode,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => _shell(
      title: title,
      subtitle: mode == 'ws' ? 'WebSocket connection collections' : 'HTTP request collections',
      width: 440,
      child: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(fontSize: 12.5),
        decoration: astraInput(hint: 'Collection name'),
        onSubmitted: (value) => Navigator.of(ctx).pop(value),
      ),
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
        SizedBox(width: 10),
        GradientButton(
          label: 'OK',
          onPressed: () => Navigator.of(ctx).pop(controller.text),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/* ------------------------------------------------------------------ */
/* 导出                                                                */
/* ------------------------------------------------------------------ */

Future<String?> showExportDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _shell(
      title: 'Export Workspace',
      subtitle: 'Choose a format, then pick where to save the file.',
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ExportOption(
            icon: Icons.auto_awesome_outlined,
            title: 'Astra Backup (Recommended)',
            description: 'Includes environments, collections and cookies. '
                'Can be imported back into Astra.',
            onTap: () => Navigator.of(ctx).pop('astra'),
          ),
          SizedBox(height: 8),
          _ExportOption(
            icon: Icons.swap_horiz_rounded,
            title: 'Postman Collection v2.1',
            description: 'Export as a Postman collection file to share with other tools.',
            onTap: () => Navigator.of(ctx).pop('postman'),
          ),
          SizedBox(height: 8),
          _ExportOption(
            icon: Icons.cloud_queue_rounded,
            title: 'Insomnia v4',
            description: 'Export as an Insomnia export file, including environments.',
            onTap: () => Navigator.of(ctx).pop('insomnia'),
          ),
          SizedBox(height: 8),
          _ExportOption(
            icon: Icons.description_outlined,
            title: 'OpenAPI 3.0',
            description: 'Generate OpenAPI docs from your requests, ready for API documentation sites.',
            onTap: () => Navigator.of(ctx).pop('openapi'),
          ),
        ],
      ),
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}

class _ExportOption extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  _ExportOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  State<_ExportOption> createState() => _ExportOptionState();
}

class _ExportOptionState extends State<_ExportOption> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 140),
          padding: EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _hover ? AstraColors.accentSoft : AstraColors.overlay,
            border: Border.all(color: _hover ? AstraColors.lineStrong : AstraColors.line),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AstraColors.accent.withValues(alpha: 0.18),
                      AstraColors.accent2.withValues(alpha: 0.18),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(widget.icon, size: 17, color: AstraColors.accent),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 3),
                    Text(
                      widget.description,
                      style: TextStyle(fontSize: 11, color: AstraColors.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: AstraColors.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/* 确认                                                                */
/* ------------------------------------------------------------------ */

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => _shell(
      title: title,
      width: 420,
      child: Text(
        message,
        style: TextStyle(fontSize: 12.5, color: AstraColors.muted, height: 1.7),
      ),
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
        SizedBox(width: 10),
        GradientButton(
          label: confirmLabel,
          danger: true,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return result == true;
}

Future<void> showMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
  bool error = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _shell(
      title: title,
      width: 440,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: error ? AstraColors.err : AstraColors.accent,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: AstraColors.muted, height: 1.7),
            ),
          ),
        ],
      ),
      actions: [
        GradientButton(label: 'Got it', onPressed: () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}

/* ------------------------------------------------------------------ */
/* cURL 导入                                                           */
/* ------------------------------------------------------------------ */

/// 粘贴 cURL 命令并解析为请求，成功后由调用方新建标签页。
Future<void> showCurlImportDialog(BuildContext context, AppState state) async {
  final controller = TextEditingController();
  String? error;
  final source = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => _shell(
        title: 'Import from cURL',
        subtitle: 'Paste a "Copy as cURL" command from the browser or any cURL command. '
            'Astra will parse the URL, method, headers, authorization and body.',
        width: 680,
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
                hint: "curl -X POST 'https://api.demo.com/users' \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"name\":\"astra\"}'",
                contentPadding: EdgeInsets.all(11),
              ),
            ),
            if (error != null) ...[
              SizedBox(height: 10),
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
              final text = controller.text.trim();
              if (text.isEmpty) {
                setLocal(() => error = 'Paste a cURL command first');
                return;
              }
              try {
                state.parseCurl(text);
              } on FormatException catch (err) {
                setLocal(() => error = err.message);
                return;
              } catch (err) {
                setLocal(() => error = 'Failed to parse: $err');
                return;
              }
              Navigator.of(ctx).pop(text);
            },
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  if (source == null || source.trim().isEmpty) return;
  try {
    state.openCurl(source);
  } catch (err) {
    state.showToast('Import failed: $err');
  }
}


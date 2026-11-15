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
    insetPadding: const EdgeInsets.all(32),
    child: Container(
      width: width,
      constraints: const BoxConstraints(maxHeight: 660),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: AstraColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AstraColors.line),
        boxShadow: const [
          BoxShadow(color: Color(0x8C000000), blurRadius: 60, offset: Offset(0, 24)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11.5, color: AstraColors.muted, height: 1.6),
            ),
          ],
          const SizedBox(height: 16),
          Flexible(child: child),
          const SizedBox(height: 18),
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
        title: '环境管理',
        subtitle: '为开发 / 测试 / 生产分别维护变量集合，请求中使用 {{变量名}} 引用当前环境的值。',
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
                            title: '删除环境',
                            message: '确定删除环境「${env.name}」及其变量吗？此操作不可撤销。',
                          );
                          if (!ok) return;
                          if (!state.deleteEnv(env.id)) {
                            state.showToast('至少需要保留一个环境');
                          }
                          setLocal(() {});
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                label: '新建环境',
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
            label: '完成',
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

  const _EnvRow({
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: active ? const Color(0x1238BDF8) : const Color(0x08FFFFFF),
        border: Border.all(
          color: active ? const Color(0x3338BDF8) : AstraColors.line,
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
          const SizedBox(width: 10),
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
                        style: const TextStyle(fontSize: 12.5, color: AstraColors.text),
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0x2638BDF8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '当前',
                          style: TextStyle(fontSize: 9, color: AstraColors.accent),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$count 个变量',
                  style: const TextStyle(fontSize: 10, color: AstraColors.faint),
                ),
              ],
            ),
          ),
          if (!active)
            TextButton(
              onPressed: onSwitch,
              style: TextButton.styleFrom(
                foregroundColor: AstraColors.accent,
                textStyle: const TextStyle(fontSize: 11),
              ),
              child: const Text('切换'),
            ),
          IconButton(
            tooltip: '编辑变量',
            onPressed: onEdit,
            iconSize: 15,
            color: AstraColors.muted,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '复制环境',
            onPressed: onDuplicate,
            iconSize: 15,
            color: AstraColors.muted,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: '删除环境',
            onPressed: onDelete,
            iconSize: 15,
            color: AstraColors.faint,
            icon: const Icon(Icons.delete_outline),
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
  final nameController = TextEditingController(text: existing?.name ?? '新环境');
  final vars = (existing?.vars ?? [KV()]).map((item) => item.copy()).toList();
  if (vars.isEmpty) vars.add(KV());

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => _shell(
        title: existing == null ? '新建环境' : '编辑环境',
        subtitle: '在请求中使用 {{变量名}} 引用；发送前会自动替换为当前环境的值。',
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(fontSize: 12.5),
                decoration: astraInput(hint: '环境名称，例如 开发 / 测试 / 生产'),
              ),
              const SizedBox(height: 16),
              KVEditor(
                rows: vars,
                onChanged: () {},
                keyHint: '变量名',
                valueHint: '变量值',
                onAdd: () => setLocal(() => vars.add(KV())),
                onRemove: (index) => setLocal(() => vars.removeAt(index)),
              ),
            ],
          ),
        ),
        actions: [
          GhostButton(
            label: '取消',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: 10),
          GradientButton(
            label: '保存',
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
    final name = nameController.text.trim().isEmpty ? '环境' : nameController.text.trim();
    final targetId = existing?.id ?? state.createEnv(name).id;
    state.updateEnvById(targetId, name, cleaned.isEmpty ? [KV()] : cleaned);
    state.showToast('环境「$name」已保存');
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
        title: 'Cookie 管理',
        subtitle: '响应中的 Set-Cookie 会自动写入，并在请求时按域与路径匹配携带。',
        width: 780,
        child: state.cookies.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: EmptyHint(
                  icon: Icons.cookie_outlined,
                  title: '暂无 Cookie',
                  subtitle: '发送携带 Set-Cookie 的请求后会自动出现在这里',
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6, left: 6, right: 6),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: _Th('名称')),
                          Expanded(flex: 3, child: _Th('值')),
                          Expanded(flex: 2, child: _Th('域')),
                          Expanded(flex: 2, child: _Th('路径')),
                          Expanded(flex: 2, child: _Th('过期')),
                          SizedBox(width: 36),
                        ],
                      ),
                    ),
                    ...List.generate(state.cookies.length, (index) {
                      final cookie = state.cookies[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                        decoration: const BoxDecoration(
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
                                    ? '会话'
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
                                tooltip: '删除',
                                onPressed: () {
                                  state.deleteCookie(index);
                                  setLocal(() {});
                                },
                                icon: const Icon(Icons.close, size: 15),
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
            label: '清空全部',
            onPressed: state.cookies.isEmpty
                ? null
                : () {
                    state.clearCookies();
                    setLocal(() {});
                  },
          ),
          const SizedBox(width: 10),
          GradientButton(
            label: '完成',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    ),
  );
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 10, color: AstraColors.faint, letterSpacing: 0.6),
      );
}

/* ------------------------------------------------------------------ */
/* 保存请求                                                            */
/* ------------------------------------------------------------------ */

class SaveRequestResult {
  final String name;
  final String groupId;
  final String folderId;

  const SaveRequestResult(this.name, this.groupId, this.folderId);
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
          ? (state.ws.url.isEmpty ? '未命名 WebSocket' : state.ws.url)
          : (state.request.url.isEmpty ? '未命名请求' : state.request.url));
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
          title: existing == null ? '保存到集合' : '更新集合中的请求',
          subtitle: state.mode == 'ws'
              ? 'WebSocket 连接会按集合 / 文件夹归档，下次可从侧栏一键载入。'
              : '选择请求归属的集合与文件夹，便于按业务模块归档。',
          width: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(fontSize: 12.5),
                decoration: astraInput(hint: '名称'),
                onSubmitted: (value) =>
                    Navigator.of(ctx).pop(SaveRequestResult(value, groupId, folderId)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _selectBox(
                      value: groupId,
                      hint: '未分组',
                      items: [
                        const DropdownMenuItem(value: '', child: Text('未分组')),
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
                  const SizedBox(width: 8),
                  GhostButton(
                    label: '新建集合',
                    icon: Icons.create_new_folder_outlined,
                    onPressed: () async {
                      final name = await showGroupDialog(
                        ctx,
                        title: '新建集合',
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _selectBox(
                        value: folderId,
                        hint: '集合根目录',
                        items: [
                          const DropdownMenuItem(value: '', child: Text('集合根目录')),
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
                    const SizedBox(width: 8),
                    GhostButton(
                      label: '新建文件夹',
                      icon: Icons.create_new_folder_outlined,
                      onPressed: () async {
                        final name = await showGroupDialog(
                          ctx,
                          title: '新建文件夹',
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
            GhostButton(label: '取消', onPressed: () => Navigator.of(ctx).pop()),
            const SizedBox(width: 10),
            GradientButton(
              label: '保存',
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
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF0B0F17),
      border: Border.all(color: AstraColors.line),
      borderRadius: BorderRadius.circular(9),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        dropdownColor: AstraColors.surface2,
        style: const TextStyle(fontSize: 12, color: AstraColors.text),
        hint: Text(
          hint,
          style: const TextStyle(fontSize: 12, color: AstraColors.faint),
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
      subtitle: mode == 'ws' ? 'WebSocket 连接集合' : 'HTTP 请求集合',
      width: 440,
      child: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(fontSize: 12.5),
        decoration: astraInput(hint: '集合名称'),
        onSubmitted: (value) => Navigator.of(ctx).pop(value),
      ),
      actions: [
        GhostButton(label: '取消', onPressed: () => Navigator.of(ctx).pop()),
        const SizedBox(width: 10),
        GradientButton(
          label: '确定',
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
      title: '导出工作区',
      subtitle: '选择导出格式，随后选择保存位置。',
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ExportOption(
            icon: Icons.auto_awesome_outlined,
            title: 'Astra 备份（推荐）',
            description: '完整保存环境变量、集合与 Cookie，可在 Astra 中再次导入。',
            onTap: () => Navigator.of(ctx).pop('astra'),
          ),
          const SizedBox(height: 8),
          _ExportOption(
            icon: Icons.swap_horiz_rounded,
            title: 'Postman Collection v2.1',
            description: '导出为 Postman 集合文件，便于与其他工具交换。',
            onTap: () => Navigator.of(ctx).pop('postman'),
          ),
          const SizedBox(height: 8),
          _ExportOption(
            icon: Icons.description_outlined,
            title: 'OpenAPI 3.0',
            description: '根据请求自动生成 OpenAPI 文档，可直接用于接口文档站。',
            onTap: () => Navigator.of(ctx).pop('openapi'),
          ),
        ],
      ),
      actions: [
        GhostButton(label: '取消', onPressed: () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}

class _ExportOption extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ExportOption({
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
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _hover ? const Color(0x0F38BDF8) : const Color(0x08FFFFFF),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.description,
                      style: const TextStyle(fontSize: 11, color: AstraColors.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AstraColors.faint),
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
  String confirmLabel = '删除',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => _shell(
      title: title,
      width: 420,
      child: Text(
        message,
        style: const TextStyle(fontSize: 12.5, color: AstraColors.muted, height: 1.7),
      ),
      actions: [
        GhostButton(label: '取消', onPressed: () => Navigator.of(ctx).pop(false)),
        const SizedBox(width: 10),
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
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, color: AstraColors.muted, height: 1.7),
            ),
          ),
        ],
      ),
      actions: [
        GradientButton(label: '知道了', onPressed: () => Navigator.of(ctx).pop()),
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
        title: '从 cURL 导入',
        subtitle: '粘贴浏览器「Copy as cURL」或任意 cURL 命令，Astra 会解析出地址、方法、Header、认证与 Body。',
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
                contentPadding: const EdgeInsets.all(11),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(fontSize: 11.5, color: AstraColors.err)),
            ],
          ],
        ),
        actions: [
          GhostButton(
            label: '取消',
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          const SizedBox(width: 8),
          GradientButton(
            label: '导入',
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                setLocal(() => error = '请先粘贴 cURL 命令');
                return;
              }
              try {
                state.parseCurl(text);
              } on FormatException catch (err) {
                setLocal(() => error = err.message);
                return;
              } catch (err) {
                setLocal(() => error = '解析失败：$err');
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
    state.showToast('导入失败：$err');
  }
}


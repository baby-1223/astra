import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import 'advanced_dialogs.dart';
import 'bound_text_field.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class Sidebar extends StatefulWidget {
  final AppState state;

  const Sidebar({super.key, required this.state});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  String tab = 'collections';
  bool _historySelectMode = false;
  final Set<String> _selectedHistory = {};
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleHistorySelect(String id) {
    setState(() {
      if (_selectedHistory.contains(id)) {
        _selectedHistory.remove(id);
      } else {
        _selectedHistory.add(id);
      }
    });
  }

  void _exitHistorySelect() {
    setState(() {
      _historySelectMode = false;
      _selectedHistory.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Container(
      width: 282,
      decoration: const BoxDecoration(
        color: AstraColors.bgSoft,
        border: Border(right: BorderSide(color: AstraColors.line)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x05FFFFFF), Color(0x00000000)],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                _tabButton('collections', state.mode == 'ws' ? '连接' : '集合',
                    state.entriesFor(state.mode).length),
                const SizedBox(width: 5),
                _tabButton('history', '历史', state.historyFor(state.mode).length),
              ],
            ),
          ),
          Expanded(
            child: tab == 'collections'
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                        child: SizedBox(
                          height: 32,
                          child: BoundTextField(
                            value: _search.text,
                            hint: state.mode == 'ws' ? '搜索连接' : '搜索请求、文件夹或集合',
                            fontSize: 11.5,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            onChanged: (value) {
                              _search.text = value;
                              setState(() {});
                            },
                          ),
                        ),
                      ),
                      Expanded(child: _collectionList(state)),
                    ],
                  )
                : _historyList(state),
          ),
          if (tab == 'history' && state.historyFor(state.mode).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  if (!_historySelectMode) ...[
                    TextButton(
                      onPressed: () => setState(() => _historySelectMode = true),
                      style: TextButton.styleFrom(
                        foregroundColor: AstraColors.faint,
                        textStyle: const TextStyle(fontSize: 11),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('多选'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final count = state.historyFor(state.mode).length;
                        final ok = await showConfirmDialog(
                          context,
                          title: '清空历史',
                          message: '将清除当前 Session 下的全部 $count 条历史记录，此操作不可撤销。',
                          confirmLabel: '清空',
                        );
                        if (ok) {
                          final ids = state
                              .historyFor(state.mode)
                              .map((item) => item.id)
                              .toSet();
                          state.deleteHistoryEntries(ids);
                          _exitHistorySelect();
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AstraColors.faint,
                        textStyle: const TextStyle(fontSize: 11),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('清空'),
                    ),
                  ] else ...[
                    Text(
                      '已选 ${_selectedHistory.length} 条',
                      style: const TextStyle(fontSize: 11, color: AstraColors.muted),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _exitHistorySelect,
                      style: TextButton.styleFrom(
                        foregroundColor: AstraColors.faint,
                        textStyle: const TextStyle(fontSize: 11),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _selectedHistory.isEmpty
                          ? null
                          : () {
                              final ids = Set<String>.from(_selectedHistory);
                              state.deleteHistoryEntries(ids);
                              _exitHistorySelect();
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: AstraColors.err,
                        textStyle: const TextStyle(fontSize: 11),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('删除选中'),
                    ),
                  ],
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AstraColors.line)),
            ),
            child: Row(
              children: [
                GradientButton(
                  label: state.mode == 'ws' ? '新建连接' : '新建请求',
                  icon: Icons.add,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onPressed: state.newRequest,
                ),
                const Spacer(),
                Text(
                  'v${AppState.version}',
                  style: const TextStyle(fontSize: 10, color: AstraColors.faint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String id, String label, int count) {
    final active = tab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => tab = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0x0DFFFFFF) : Colors.transparent,
            border: Border.all(color: active ? AstraColors.line : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.5,
                  color: active ? AstraColors.text : AstraColors.muted,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 9.5,
                  color: active ? AstraColors.accent : AstraColors.faint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collectionList(AppState state) {
    final mode = state.mode;
    final isWs = mode == 'ws';
    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) return _searchResults(state, query);
    final groups = state.groupsFor(mode);
    final entries = state.entriesFor(mode);
    final knownGroupIds = groups.map((group) => group.id).toSet();
    final ungrouped =
        entries.where((entry) => !knownGroupIds.contains(entry.groupId)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
      children: [
        _createGroupTile(state),
        if (groups.isEmpty && ungrouped.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyHint(
              icon: isWs ? Icons.electrical_services_rounded : Icons.inbox_outlined,
              title: isWs ? '还没有保存的连接' : '还没有保存的请求',
              subtitle: isWs
                  ? '配置好连接地址与 Header 后按 ⌘ / Ctrl + S，\n即可按集合归档常用 WebSocket 连接'
                  : '点击「新建集合」建立分组，\n再把请求保存到对应的集合中',
            ),
          ),
        for (final group in groups) ...[
          _groupHeader(state, group),
          if (group.expanded) ...[
            ..._folderBranch(state, group.id, '', 0),
            for (final entry in state.entriesInGroupRoot(group.id))
              _entryTile(state, entry, 0),
            for (final tab in _draftsAt(state, group.id, ''))
              _draftTile(state, tab, 0),
          ],
        ],
        if (ungrouped.isNotEmpty) ...[
          if (groups.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Text(
                '未分组',
                style: TextStyle(fontSize: 10, color: AstraColors.faint, letterSpacing: 0.6),
              ),
            ),
          for (final entry in ungrouped) _entryTile(state, entry, 0),
        ],
      ],
    );
  }

  /// 搜索模式：把匹配的请求、文件夹与集合平铺展示，便于快速定位。
  Widget _searchResults(AppState state, String query) {
    final isWs = state.mode == 'ws';
    final entries = state.entriesFor(state.mode).where((entry) {
      final url = entry.mode == 'ws' ? (entry.ws?.url ?? '') : (entry.request?.url ?? '');
      return entry.name.toLowerCase().contains(query) ||
          url.toLowerCase().contains(query) ||
          entry.description.toLowerCase().contains(query);
    }).toList();
    final folders = state.folders.where((folder) {
      final group = state.groups.where((item) => item.id == folder.groupId).firstOrNull;
      return group?.mode == state.mode && folder.name.toLowerCase().contains(query);
    }).toList();
    final groups = state.groupsFor(state.mode)
        .where((group) => group.name.toLowerCase().contains(query))
        .toList();

    if (entries.isEmpty && folders.isEmpty && groups.isEmpty) {
      return EmptyHint(
        icon: Icons.search_off_rounded,
        title: '没有匹配「$query」的结果',
        subtitle: isWs ? '试试连接名称或地址片段' : '试试请求名称、URL 或备注片段',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
      children: [
        if (groups.isNotEmpty) const _SearchSectionLabel('集合'),
        for (final group in groups)
          _SideItem(
            active: false,
            method: isWs ? 'WS' : 'API',
            name: group.name,
            url: '${state.entriesFor(state.mode).where((e) => e.groupId == group.id).length} 个条目',
            onTap: () => state.toggleGroup(group.id),
            onDelete: () {},
            hideDelete: true,
          ),
        if (folders.isNotEmpty) const _SearchSectionLabel('文件夹'),
        for (final folder in folders)
          _SideItem(
            active: false,
            method: 'DIR',
            name: folder.name,
            url: state.folderPath(folder.id),
            onTap: () => state.toggleFolder(folder.id),
            onDelete: () {},
            hideDelete: true,
          ),
        if (entries.isNotEmpty) const _SearchSectionLabel('请求'),
        for (final entry in entries) _entryTile(state, entry, 0),
      ],
    );
  }

  /// 递归渲染某个集合 / 文件夹下的子文件夹与请求
  List<Widget> _folderBranch(AppState state, String groupId, String parentId, int depth) {
    final result = <Widget>[];
    final children = state.folders
        .where((folder) => folder.groupId == groupId && folder.parentId == parentId)
        .toList();
    for (final folder in children) {
      result.add(_folderHeader(state, folder, depth));
      if (folder.expanded) {
        result.addAll(_folderBranch(state, groupId, folder.id, depth + 1));
        for (final entry in state.entriesInFolder(folder.id)) {
          result.add(_entryTile(state, entry, depth + 1));
        }
        for (final tab in _draftsAt(state, groupId, folder.id)) {
          result.add(_draftTile(state, tab, depth + 1));
        }
      }
    }
    return result;
  }

  Widget _createGroupTile(AppState state) {
    final isWs = state.mode == 'ws';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final name = await showGroupDialog(
          context,
          title: isWs ? '新建连接集合' : '新建请求集合',
          initial: '',
          mode: state.mode,
        );
        if (name == null || name.trim().isEmpty) return;
        state.createGroup(name, state.mode);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          children: [
            const Icon(Icons.add, size: 13, color: AstraColors.accent),
            const SizedBox(width: 7),
            Text(
              isWs ? '新建连接集合' : '新建集合',
              style: const TextStyle(fontSize: 11.5, color: AstraColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFolder(AppState state, CollectionGroup group, String parentId) async {
    final name = await showGroupDialog(
      context,
      title: parentId.isEmpty ? '新建文件夹' : '新建子文件夹',
      initial: '',
      mode: group.mode,
    );
    if (name == null || name.trim().isEmpty) return;
    state.createFolder(group.id, parentId, name);
  }

  Widget _groupHeader(AppState state, CollectionGroup group) {
    final isWs = group.mode == 'ws';
    final total = state.collections.where((entry) => entry.groupId == group.id).length +
        state.folders.where((folder) => folder.groupId == group.id).length;
    final header = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => state.toggleGroup(group.id),
        child: Container(
          margin: const EdgeInsets.only(top: 4, bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          child: Row(
            children: [
              AnimatedRotation(
                turns: group.expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(Icons.chevron_right, size: 14, color: AstraColors.faint),
              ),
              const SizedBox(width: 3),
              Icon(
                isWs ? Icons.folder_special_outlined : Icons.folder_outlined,
                size: 14,
                color: AstraColors.accent.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AstraColors.text,
                  ),
                ),
              ),
              Text(
                '$total',
                style: const TextStyle(fontSize: 10, color: AstraColors.faint),
              ),
              const SizedBox(width: 2),
              _MenuButton(
                tooltip: '集合操作',
                onSelected: (value) async {
                  if (value == 'api') {
                    state.newRequestIn(group.id, '');
                  } else if (value == 'folder') {
                    await _createFolder(state, group, '');
                  } else if (value == 'rename') {
                    final name = await showGroupDialog(
                      context,
                      title: '重命名集合',
                      initial: group.name,
                      mode: group.mode,
                    );
                    if (name != null) state.renameGroup(group.id, name);
                  } else if (value == 'variables') {
                    await showScopeVariablesDialog(
                      context,
                      state,
                      title: '集合变量 · ${group.name}',
                      rows: group.variables,
                      onSave: (rows) => state.setCollectionVariables(group.id, rows),
                    );
                  } else if (value == 'auth') {
                    await showScopeAuthDialog(
                      context,
                      title: '集合认证 · ${group.name}',
                      current: group.auth,
                      onSave: (auth) => state.setCollectionAuth(group.id, auth),
                    );
                  } else if (value == 'monitor') {
                    await showMonitorsDialog(context, state, group);
                  } else if (value == 'duplicate') {
                    final copy = state.duplicateGroup(group.id);
                    if (copy != null) state.showToast('已复制为「${copy.name}」');
                  } else if (value == 'delete') {
                    final ok = await showConfirmDialog(
                      context,
                      title: '删除集合',
                      message:
                          '删除「${group.name}」后，集合内的所有${isWs ? '连接' : '请求'}与文件夹都会被一并删除，此操作不可撤销。',
                    );
                    if (ok) state.deleteGroup(group.id);
                  }
                },
                items: [
                  PopupMenuItem<String>(
                    value: 'api',
                    height: 36,
                    child: Text(
                      isWs ? '新建连接' : '新建请求',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'folder',
                    height: 36,
                    child: Text('新建文件夹', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'variables',
                    height: 36,
                    child: Text('集合变量', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'auth',
                    height: 36,
                    child: Text('集合认证', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'monitor',
                    height: 36,
                    child: Text('定时监控', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'duplicate',
                    height: 36,
                    child: Text('复制集合', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'rename',
                    height: 36,
                    child: Text('重命名', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    height: 36,
                    child: Text(
                      '删除集合',
                      style: TextStyle(fontSize: 12, color: AstraColors.err),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data.startsWith('entry:'),
      onAcceptWithDetails: (details) {
        final id = details.data.substring('entry:'.length);
        state.moveEntry(id, group.id, '');
      },
      builder: (context, candidate, rejected) => Container(
        decoration: candidate.isEmpty
            ? null
            : BoxDecoration(
                color: AstraColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
        child: header,
      ),
    );
  }

  Widget _folderHeader(AppState state, CollectionFolder folder, int depth) {
    final group = state.groups.where((item) => item.id == folder.groupId).firstOrNull;
    final isWs = group?.mode == 'ws';
    final total = state.collections.where((entry) => entry.folderId == folder.id).length +
        state.folders.where((item) => item.parentId == folder.id).length;
    final header = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => state.toggleFolder(folder.id),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.only(
            left: 8 + depth * 12.0,
            right: 6,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: folder.expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(Icons.chevron_right, size: 13, color: AstraColors.faint),
              ),
              const SizedBox(width: 2),
              Icon(
                folder.expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                size: 13,
                color: AstraColors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.3, color: AstraColors.muted),
                ),
              ),
              Text(
                '$total',
                style: const TextStyle(fontSize: 9.5, color: AstraColors.faint),
              ),
              const SizedBox(width: 2),
              _MenuButton(
                tooltip: '文件夹操作',
                onSelected: (value) async {
                  if (value == 'api') {
                    state.newRequestIn(folder.groupId, folder.id);
                  } else if (value == 'folder') {
                    if (group != null) await _createFolder(state, group, folder.id);
                  } else if (value == 'rename') {
                    final name = await showGroupDialog(
                      context,
                      title: '重命名文件夹',
                      initial: folder.name,
                      mode: group?.mode ?? 'http',
                    );
                    if (name != null) state.renameFolder(folder.id, name);
                  } else if (value == 'variables') {
                    await showScopeVariablesDialog(
                      context,
                      state,
                      title: '文件夹变量 · ${folder.name}',
                      rows: folder.variables,
                      onSave: (rows) => state.setFolderVariables(folder.id, rows),
                    );
                  } else if (value == 'auth') {
                    await showScopeAuthDialog(
                      context,
                      title: '文件夹认证 · ${folder.name}',
                      current: folder.auth,
                      onSave: (auth) => state.setFolderAuth(folder.id, auth),
                    );
                  } else if (value == 'duplicate') {
                    final copy = state.duplicateFolder(folder.id);
                    if (copy != null) state.showToast('已复制为「${copy.name}」');
                  } else if (value == 'delete') {
                    final ok = await showConfirmDialog(
                      context,
                      title: '删除文件夹',
                      message: '删除「${folder.name}」后，其中的所有${isWs ? '连接' : '请求'}与子文件夹都会被一并删除，此操作不可撤销。',
                    );
                    if (ok) state.deleteFolder(folder.id);
                  }
                },
                items: [
                  PopupMenuItem<String>(
                    value: 'api',
                    height: 36,
                    child: Text(
                      isWs ? '新建连接' : '新建请求',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'folder',
                    height: 36,
                    child: Text('新建子文件夹', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'variables',
                    height: 36,
                    child: Text('文件夹变量', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'auth',
                    height: 36,
                    child: Text('文件夹认证', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'duplicate',
                    height: 36,
                    child: Text('复制文件夹', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'rename',
                    height: 36,
                    child: Text('重命名', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    height: 36,
                    child: Text(
                      '删除文件夹',
                      style: TextStyle(fontSize: 12, color: AstraColors.err),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data.startsWith('entry:'),
      onAcceptWithDetails: (details) {
        final id = details.data.substring('entry:'.length);
        state.moveEntry(id, folder.groupId, folder.id);
      },
      builder: (context, candidate, rejected) => Container(
        decoration: candidate.isEmpty
            ? null
            : BoxDecoration(
                color: AstraColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
        child: header,
      ),
    );
  }

  /// 当前在该集合 / 文件夹下尚未保存的草稿标签页
  List<WorkspaceTab> _draftsAt(AppState state, String groupId, String folderId) =>
      state.tabs
          .where((tab) =>
              tab.entryId.isEmpty && tab.groupId == groupId && tab.folderId == folderId)
          .toList();

  Widget _draftTile(AppState state, WorkspaceTab tab, int depth) {
    final isWs = tab.mode == 'ws';
    return _SideItem(
      active: tab.id == state.activeTabId,
      indent: depth * 12.0,
      method: isWs ? 'WS' : tab.request.method,
      name: '${tab.name}（草稿）',
      url: '未保存 · 按 ⌘ / Ctrl + S 保存',
      onTap: () => state.activateTab(tab.id),
      onDelete: () => state.closeTab(tab.id),
    );
  }

  Widget _entryTile(AppState state, CollectionEntry entry, int depth) {
    final tile = _SideItem(
      active: entry.id == state.selectedId,
      indent: depth * 12.0,
      method: entry.mode == 'ws' ? 'WS' : (entry.request?.method ?? 'GET'),
      name: entry.name,
      url: entry.mode == 'ws' ? (entry.ws?.url ?? '') : (entry.request?.url ?? ''),
      tooltip: entry.description.isEmpty ? null : entry.description,
      onTap: () => state.openEntry(entry),
      onDelete: () async {
        final ok = await showConfirmDialog(
          context,
          title: '删除${entry.mode == 'ws' ? '连接' : '请求'}',
          message: '确定删除「${entry.name}」吗？此操作不可撤销。',
        );
        if (ok) state.deleteEntry(entry.id);
      },
      onMenuSelected: (value) async {
        switch (value) {
          case 'meta':
            await showEntryMetaDialog(context, state, entry.id);
            break;
          case 'duplicate':
            final copy = state.duplicateEntry(entry.id);
            if (copy != null) state.showToast('已复制为「${copy.name}」');
            break;
          case 'move':
            await showMoveEntryDialog(context, state, entry.id);
            break;
          case 'examples':
            await showExamplesDialog(context, state, entry.id);
            break;
        }
      },
      menuItems: [
        const PopupMenuItem(value: 'meta', height: 36, child: Text('重命名 / 备注')),
        const PopupMenuItem(value: 'duplicate', height: 36, child: Text('复制请求')),
        const PopupMenuItem(value: 'move', height: 36, child: Text('移动到…')),
        const PopupMenuItem(value: 'examples', height: 36, child: Text('响应示例')),
      ],
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data.startsWith('entry:') && details.data != 'entry:${entry.id}',
      onAcceptWithDetails: (details) {
        final id = details.data.substring('entry:'.length);
        state.moveEntryBefore(id, entry.id);
      },
      builder: (context, candidate, rejected) => Container(
        decoration: candidate.isEmpty
            ? null
            : const BoxDecoration(
                border: Border(top: BorderSide(color: AstraColors.accent, width: 1.5)),
              ),
        child: LongPressDraggable<String>(
          data: 'entry:${entry.id}',
          feedback: _dragFeedback(entry.mode == 'ws' ? 'WS' : (entry.request?.method ?? 'GET'),
              entry.name),
          childWhenDragging: Opacity(opacity: 0.4, child: tile),
          child: tile,
        ),
      ),
    );
  }

  Widget _dragFeedback(String method, String name) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AstraColors.surface2,
          border: Border.all(color: AstraColors.accent),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 12)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MethodBadge(method: method),
            const SizedBox(width: 8),
            Text(name, style: const TextStyle(fontSize: 11.5, color: AstraColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _historyList(AppState state) {
    final items = state.historyFor(state.mode);
    if (items.isEmpty) {
      return const EmptyHint(
        icon: Icons.history_rounded,
        title: '暂无历史记录',
        subtitle: '每次发送请求后，\n这里会保留最近 80 条记录',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final entry = items[index];
        return _HistoryItem(
          entry: entry,
          selectMode: _historySelectMode,
          selected: _selectedHistory.contains(entry.id),
          onTap: () => state.openHistory(entry),
          onToggle: () => _toggleHistorySelect(entry.id),
          onDelete: () => state.deleteHistoryEntry(entry.id),
        );
      },
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String tooltip;
  final ValueChanged<String> onSelected;
  final List<PopupMenuEntry<String>> items;

  const _MenuButton({
    required this.tooltip,
    required this.onSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: PopupMenuButton<String>(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: AstraColors.surface2,
        onSelected: onSelected,
        itemBuilder: (ctx) => items,
        child: const Icon(Icons.more_horiz, size: 15, color: AstraColors.faint),
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  final bool active;
  final double indent;
  final String method;
  final String name;
  final String url;
  final String? tooltip;
  final bool hideDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<String>? onMenuSelected;
  final List<PopupMenuEntry<String>>? menuItems;

  const _SideItem({
    required this.active,
    required this.method,
    required this.name,
    required this.url,
    required this.onTap,
    required this.onDelete,
    this.indent = 0,
    this.tooltip,
    this.hideDelete = false,
    this.onMenuSelected,
    this.menuItems,
  });

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final content = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.only(bottom: 3),
          padding: EdgeInsets.fromLTRB(9 + widget.indent, 8, 9, 8),
          decoration: BoxDecoration(
            color: widget.active
                ? const Color(0x1238BDF8)
                : _hover
                    ? const Color(0x0AFFFFFF)
                    : Colors.transparent,
            border: Border.all(
              color: widget.active
                  ? const Color(0x3338BDF8)
                  : _hover
                      ? AstraColors.line
                      : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              MethodBadge(method: widget.method),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AstraColors.text),
                    ),
                    if (widget.url.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(size: 10.5, color: AstraColors.faint),
                      ),
                    ],
                  ],
                ),
              ),
              if (_hover || widget.active) ...[
                if (widget.menuItems != null)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: PopupMenuButton<String>(
                      tooltip: '更多操作',
                      padding: EdgeInsets.zero,
                      color: AstraColors.surface2,
                      onSelected: widget.onMenuSelected,
                      itemBuilder: (ctx) => widget.menuItems!,
                      child: const Icon(Icons.more_horiz, size: 15, color: AstraColors.faint),
                    ),
                  ),
                if (!widget.hideDelete)
                  SizedBox(
                    width: 24,
                    child: IconButton(
                      onPressed: widget.onDelete,
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      tooltip: '删除',
                      color: AstraColors.faint,
                      highlightColor: const Color(0x1AFB7185),
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip == null) return content;
    return Tooltip(
      message: widget.tooltip!,
      waitDuration: const Duration(milliseconds: 600),
      child: content,
    );
  }
}

class _SearchSectionLabel extends StatelessWidget {
  final String text;

  const _SearchSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 5),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: AstraColors.faint, letterSpacing: 0.6),
      ),
    );
  }
}

class _HistoryItem extends StatefulWidget {
  final HistoryEntry entry;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _HistoryItem({
    required this.entry,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<_HistoryItem> createState() => _HistoryItemState();
}

class _HistoryItemState extends State<_HistoryItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.selectMode ? widget.onToggle : widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? const Color(0x1438BDF8)
                : _hover
                    ? const Color(0x0AFFFFFF)
                    : Colors.transparent,
            border: Border.all(
              color: widget.selected
                  ? AstraColors.accent
                  : _hover
                      ? AstraColors.line
                      : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              if (widget.selectMode) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: Checkbox(
                    value: widget.selected,
                    onChanged: (_) => widget.onToggle(),
                    activeColor: AstraColors.accent,
                    side: const BorderSide(color: AstraColors.lineStrong, width: 1),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              MethodBadge(method: entry.method),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(size: 10.5, color: AstraColors.muted),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: statusColor(entry.status),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          entry.status == null ? '失败' : '${entry.status}',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: statusColor(entry.status),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entry.ms} ms',
                          style: const TextStyle(fontSize: 9.5, color: AstraColors.faint),
                        ),
                        const Spacer(),
                        Text(
                          formatTime(entry.ts),
                          style: const TextStyle(fontSize: 9.5, color: AstraColors.faint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!widget.selectMode && _hover) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    tooltip: '删除该条历史',
                    padding: EdgeInsets.zero,
                    iconSize: 13,
                    color: AstraColors.faint,
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

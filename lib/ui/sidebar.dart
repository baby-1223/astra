import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import 'advanced_dialogs.dart';
import 'bound_text_field.dart';
import 'dialogs.dart';
import 'runner_dialog.dart';
import 'theme.dart';
import 'traffic_dialog.dart';
import 'widgets.dart';

part 'sidebar/widgets.dart';

class Sidebar extends StatefulWidget {
  final AppState state;

  Sidebar({super.key, required this.state});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  String tab = 'collections';
  bool _historySelectMode = false;
  final Set<String> _selectedHistory = {};
  final TextEditingController _search = TextEditingController();
  bool _starredOnly = false;

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
      decoration: BoxDecoration(
        color: AstraColors.bgSoft,
        border: Border(right: BorderSide(color: AstraColors.line)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AstraColors.overlay, Color(0x00000000)],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                _tabButton('collections', state.mode == 'ws' ? 'Connections' : 'Collections',
                    state.entriesFor(state.mode).length),
                SizedBox(width: 5),
                _tabButton('history', 'History', state.historyFor(state.mode).length),
              ],
            ),
          ),
          Expanded(
            child: tab == 'collections'
                ? Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(14, 2, 14, 6),
                        child: SizedBox(
                          height: 32,
                          child: Row(
                            children: [
                              Expanded(
                                child: BoundTextField(
                                  value: _search.text,
                                  hint: state.mode == 'ws'
                                      ? 'Search connections'
                                      : 'Search requests, folders or collections',
                                  fontSize: 11.5,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 7),
                                  onChanged: (value) {
                                    _search.text = value;
                                    setState(() {});
                                  },
                                ),
                              ),
                              SizedBox(width: 6),
                              _StarFilterButton(
                                active: _starredOnly,
                                onTap: () =>
                                    setState(() => _starredOnly = !_starredOnly),
                              ),
                            ],
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
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  if (!_historySelectMode) ...[
                    TextButton(
                      onPressed: () => setState(() => _historySelectMode = true),
                      style: TextButton.styleFrom(
                        foregroundColor: AstraColors.faint,
                        textStyle: TextStyle(fontSize: 11),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text('Select'),
                    ),
                    Spacer(),
                    TextButton(
                      onPressed: () async {
                        final count = state.historyFor(state.mode).length;
                        final ok = await showConfirmDialog(
                          context,
                          title: 'Clear History',
                          message:
                              'This will delete all $count history entries in the current session. This cannot be undone.',
                          confirmLabel: 'Clear',
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
                        textStyle: TextStyle(fontSize: 11),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text('Clear'),
                    ),
                  ] else ...[
                    Text(
                      '${_selectedHistory.length} selected',
                      style: TextStyle(fontSize: 11, color: AstraColors.muted),
                    ),
                    Spacer(),
                    TextButton(
                      onPressed: _exitHistorySelect,
                      style: TextButton.styleFrom(
                        foregroundColor: AstraColors.faint,
                        textStyle: TextStyle(fontSize: 11),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text('Cancel'),
                    ),
                    SizedBox(width: 8),
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
                        textStyle: TextStyle(fontSize: 11),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text('Delete Selected'),
                    ),
                  ],
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AstraColors.line)),
            ),
            child: Row(
              children: [
                Tooltip(
                  message: state.mode == 'ws' ? 'New Connection' : 'New Request',
                  child: GradientButton(
                    label: 'New',
                    icon: Icons.add,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    onPressed: state.newRequest,
                  ),
                ),
                Spacer(),
                Text(
                  'v${AppState.version}',
                  style: TextStyle(fontSize: 10, color: AstraColors.faint),
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
          padding: EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AstraColors.overlay : Colors.transparent,
            border: Border.all(color: active ? AstraColors.line : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.5,
                    color: active ? AstraColors.text : AstraColors.muted,
                  ),
                ),
              ),
              SizedBox(width: 5),
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

  /// Starred collections come first while keeping the user's order inside each bucket.
  List<CollectionGroup> _orderedGroups(
    AppState state,
    String mode, {
    bool applyFilter = true,
  }) {
    var groups = state.groupsFor(mode);
    if (applyFilter && _starredOnly) {
      groups = groups.where((group) => group.starred).toList();
    }
    return [
      ...groups.where((group) => group.starred),
      ...groups.where((group) => !group.starred),
    ];
  }

  Widget _collectionList(AppState state) {
    final mode = state.mode;
    final isWs = mode == 'ws';
    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) return _searchResults(state, query);
    final groups = _orderedGroups(state, mode);
    final entries = state.entriesFor(mode);
    final knownGroupIds = state.groupsFor(mode).map((group) => group.id).toSet();
    final ungrouped =
        entries.where((entry) => !knownGroupIds.contains(entry.groupId)).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(10, 4, 10, 12),
      children: [
        _createGroupTile(state),
        if (groups.isEmpty && ungrouped.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyHint(
              icon: _starredOnly
                  ? Icons.star_outline_rounded
                  : isWs
                      ? Icons.electrical_services_rounded
                      : Icons.inbox_outlined,
              title: _starredOnly
                  ? 'No starred collections'
                  : isWs
                      ? 'No saved connections yet'
                      : 'No saved requests yet',
              subtitle: _starredOnly
                  ? 'Click the star on a collection to pin it to the top'
                  : isWs
                      ? 'Configure the connection URL and headers, then press ⌘ / Ctrl + S\nto save frequently used WebSocket connections into a collection'
                      : 'Click "New Collection" to create a group,\nthen save requests into it',
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
            Padding(
              padding: EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Text(
                'Ungrouped',
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
    final groups = _orderedGroups(state, state.mode, applyFilter: false)
        .where((group) => group.name.toLowerCase().contains(query))
        .toList();

    if (entries.isEmpty && folders.isEmpty && groups.isEmpty) {
      return EmptyHint(
        icon: Icons.search_off_rounded,
        title: 'No results for "$query"',
        subtitle: isWs ? 'Try a connection name or part of the URL' : 'Try a request name, URL or description',
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(10, 4, 10, 12),
      children: [
        if (groups.isNotEmpty) _SearchSectionLabel('Collections'),
        for (final group in groups)
          _SideItem(
            active: false,
            method: isWs ? 'WS' : 'API',
            name: group.name,
            url: '${state.entriesFor(state.mode).where((e) => e.groupId == group.id).length} items',
            onTap: () => state.toggleGroup(group.id),
            onDelete: () {},
            hideDelete: true,
          ),
        if (folders.isNotEmpty) _SearchSectionLabel('Folders'),
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
        if (entries.isNotEmpty) _SearchSectionLabel('Requests'),
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
          title: isWs ? 'New Connection Collection' : 'New Request Collection',
          initial: '',
          mode: state.mode,
        );
        if (name == null || name.trim().isEmpty) return;
        state.createGroup(name, state.mode);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          children: [
            Icon(Icons.add, size: 13, color: AstraColors.accent),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                isWs ? 'New Connection Collection' : 'New Collection',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: AstraColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMenu(
    Offset position,
    List<PopupMenuEntry<String>> items,
    ValueChanged<String> onSelected,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: AstraColors.surface2,
      items: items,
    );
    if (selected != null) onSelected(selected);
  }

  List<PopupMenuEntry<String>> _groupMenuItems(CollectionGroup group, bool isWs) {
    return [
      PopupMenuItem<String>(
        value: 'api',
        height: 36,
        child: Text(
          isWs ? 'New Connection' : 'Add Request',
          style: TextStyle(fontSize: 12),
        ),
      ),
      PopupMenuItem<String>(
        value: 'folder',
        height: 36,
        child: Text('Add Folder', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'run',
        height: 36,
        child: Text('Run Collection', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'star',
        height: 36,
        child: Text(
          group.starred ? 'Unstar Collection' : 'Star Collection',
          style: TextStyle(fontSize: 12),
        ),
      ),
      PopupMenuItem<String>(
        value: 'variables',
        height: 36,
        child: Text('Variables', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuItem<String>(
        value: 'auth',
        height: 36,
        child: Text('Authorization', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuItem<String>(
        value: 'monitor',
        height: 36,
        child: Text('Monitors', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuItem<String>(
        value: 'duplicate',
        height: 36,
        child: Text('Duplicate', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuItem<String>(
        value: 'rename',
        height: 36,
        child: Text('Rename', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'delete',
        height: 36,
        child: Text(
          'Delete Collection',
          style: TextStyle(fontSize: 12, color: AstraColors.err),
        ),
      ),
    ];
  }

  Future<void> _handleGroupAction(
    AppState state,
    CollectionGroup group,
    String value,
  ) async {
    final isWs = group.mode == 'ws';
    switch (value) {
      case 'api':
        state.newRequestIn(group.id, '');
        break;
      case 'folder':
        await _createFolder(state, group, '');
        break;
      case 'run':
        await showRunnerDialog(context, state, groupId: group.id);
        break;
      case 'rename':
        final name = await showGroupDialog(
          context,
          title: 'Rename Collection',
          initial: group.name,
          mode: group.mode,
        );
        if (name != null) state.renameGroup(group.id, name);
        break;
      case 'variables':
        await showScopeVariablesDialog(
          context,
          state,
          title: 'Collection Variables · ${group.name}',
          rows: group.variables,
          onSave: (rows) => state.setCollectionVariables(group.id, rows),
        );
        break;
      case 'auth':
        await showScopeAuthDialog(
          context,
          title: 'Collection Authorization · ${group.name}',
          current: group.auth,
          onSave: (auth) => state.setCollectionAuth(group.id, auth),
        );
        break;
      case 'star':
        state.setGroupStarred(group.id, !group.starred);
        break;
      case 'monitor':
        await showMonitorsDialog(context, state, group);
        break;
      case 'duplicate':
        final copy = state.duplicateGroup(group.id);
        if (copy != null) state.showToast('Copied as "${copy.name}"');
        break;
      case 'delete':
        final ok = await showConfirmDialog(
          context,
          title: 'Delete Collection',
          message:
              'Deleting "${group.name}" also removes every ${isWs ? 'connection' : 'request'} and folder inside it. This cannot be undone.',
        );
        if (ok) state.deleteGroup(group.id);
        break;
    }
  }

  List<PopupMenuEntry<String>> _folderMenuItems(bool isWs) {
    return [
      PopupMenuItem<String>(
        value: 'api',
        height: 36,
        child: Text(
          isWs ? 'New Connection' : 'Add Request',
          style: TextStyle(fontSize: 12),
        ),
      ),
      PopupMenuItem<String>(
        value: 'folder',
        height: 36,
        child: Text('Add Folder', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'run',
        height: 36,
        child: Text('Run Folder', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'variables',
        height: 36,
        child: Text('Variables', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuItem<String>(
        value: 'auth',
        height: 36,
        child: Text('Authorization', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuItem<String>(
        value: 'duplicate',
        height: 36,
        child: Text('Duplicate', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuItem<String>(
        value: 'rename',
        height: 36,
        child: Text('Rename', style: TextStyle(fontSize: 12)),
      ),
      PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'delete',
        height: 36,
        child: Text(
          'Delete Folder',
          style: TextStyle(fontSize: 12, color: AstraColors.err),
        ),
      ),
    ];
  }

  Future<void> _handleFolderAction(
    AppState state,
    CollectionGroup? group,
    CollectionFolder folder,
    String value,
  ) async {
    final isWs = group?.mode == 'ws';
    switch (value) {
      case 'api':
        state.newRequestIn(folder.groupId, folder.id);
        break;
      case 'folder':
        if (group != null) await _createFolder(state, group, folder.id);
        break;
      case 'run':
        await showRunnerDialog(
          context,
          state,
          groupId: folder.groupId,
          folderId: folder.id,
        );
        break;
      case 'rename':
        final name = await showGroupDialog(
          context,
          title: 'Rename Folder',
          initial: folder.name,
          mode: group?.mode ?? 'http',
        );
        if (name != null) state.renameFolder(folder.id, name);
        break;
      case 'variables':
        await showScopeVariablesDialog(
          context,
          state,
          title: 'Folder Variables · ${folder.name}',
          rows: folder.variables,
          onSave: (rows) => state.setFolderVariables(folder.id, rows),
        );
        break;
      case 'auth':
        await showScopeAuthDialog(
          context,
          title: 'Folder Authorization · ${folder.name}',
          current: folder.auth,
          onSave: (auth) => state.setFolderAuth(folder.id, auth),
        );
        break;
      case 'duplicate':
        final copy = state.duplicateFolder(folder.id);
        if (copy != null) state.showToast('Copied as "${copy.name}"');
        break;
      case 'delete':
        final ok = await showConfirmDialog(
          context,
          title: 'Delete Folder',
          message:
              'Deleting "${folder.name}" also removes every ${isWs == true ? 'connection' : 'request'} and subfolder inside it. This cannot be undone.',
        );
        if (ok) state.deleteFolder(folder.id);
        break;
    }
  }

  Future<void> _createFolder(AppState state, CollectionGroup group, String parentId) async {
    final name = await showGroupDialog(
      context,
      title: parentId.isEmpty ? 'New Folder' : 'New Subfolder',
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
        onTap: () {
          state.selectTreeNode('group', group.id);
          state.toggleGroup(group.id);
        },
        onSecondaryTapDown: (details) => _showMenu(
          details.globalPosition,
          _groupMenuItems(group, isWs),
          (value) => _handleGroupAction(state, group, value),
        ),
        child: Container(
          margin: EdgeInsets.only(top: 4, bottom: 3),
          padding: EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          decoration: BoxDecoration(
            color: state.selectedNodeKind == 'group' &&
                    state.selectedNodeId == group.id
                ? AstraColors.overlay
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: group.expanded ? 0.25 : 0,
                duration: Duration(milliseconds: 150),
                child: Icon(Icons.chevron_right, size: 14, color: AstraColors.faint),
              ),
              SizedBox(width: 3),
              Icon(
                isWs ? Icons.folder_special_outlined : Icons.folder_outlined,
                size: 14,
                color: AstraColors.accent.withValues(alpha: 0.8),
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AstraColors.text,
                  ),
                ),
              ),
              Text(
                '$total',
                style: TextStyle(fontSize: 10, color: AstraColors.faint),
              ),
              SizedBox(width: 2),
              _GroupStarButton(
                starred: group.starred,
                onTap: () => state.setGroupStarred(group.id, !group.starred),
              ),
              SizedBox(width: 2),
              Icon(Icons.more_horiz, size: 15, color: AstraColors.faint),
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
        onTap: () {
          state.selectTreeNode('folder', folder.id);
          state.toggleFolder(folder.id);
        },
        onSecondaryTapDown: (details) => _showMenu(
          details.globalPosition,
          _folderMenuItems(isWs == true),
          (value) => _handleFolderAction(state, group, folder, value),
        ),
        child: Container(
          margin: EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.only(
            left: 8 + depth * 12.0,
            right: 6,
            top: 6,
            bottom: 6,
          ),
          decoration: BoxDecoration(
            color: state.selectedNodeKind == 'folder' &&
                    state.selectedNodeId == folder.id
                ? AstraColors.overlay
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: folder.expanded ? 0.25 : 0,
                duration: Duration(milliseconds: 150),
                child: Icon(Icons.chevron_right, size: 13, color: AstraColors.faint),
              ),
              SizedBox(width: 2),
              Icon(
                folder.expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                size: 13,
                color: AstraColors.muted,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.3, color: AstraColors.muted),
                ),
              ),
              Text(
                '$total',
                style: TextStyle(fontSize: 9.5, color: AstraColors.faint),
              ),
              SizedBox(width: 2),
              Icon(Icons.more_horiz, size: 15, color: AstraColors.faint),
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
      name: '${tab.name} (Draft)',
      url: 'Unsaved · Press ⌘ / Ctrl + S to save',
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
      onTap: () {
        state.selectTreeNode('entry', entry.id);
        state.openEntry(entry);
      },
      onDelete: () async {
        final ok = await showConfirmDialog(
          context,
          title: 'Delete ${entry.mode == 'ws' ? 'Connection' : 'Request'}',
          message: 'Delete "${entry.name}"? This cannot be undone.',
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
            if (copy != null) state.showToast('Copied as "${copy.name}"');
            break;
          case 'move':
            await showMoveEntryDialog(context, state, entry.id);
            break;
          case 'examples':
            await showExamplesDialog(context, state, entry.id);
            break;
          case 'mock':
            await showTrafficStudioDialog(
              context,
              state,
              initialTab: 'mock',
              draftRoute: state.mockRouteForEntry(entry),
            );
            break;
          case 'delete':
            final ok = await showConfirmDialog(
              context,
              title: 'Delete ${entry.mode == 'ws' ? 'Connection' : 'Request'}',
              message: 'Delete "${entry.name}"? This cannot be undone.',
            );
            if (ok) state.deleteEntry(entry.id);
            break;
        }
      },
      menuItems: [
        PopupMenuItem(value: 'meta', height: 36, child: Text('Rename / Notes')),
        PopupMenuItem(value: 'duplicate', height: 36, child: Text('Duplicate')),
        PopupMenuItem(value: 'move', height: 36, child: Text('Move to…')),
        PopupMenuItem(value: 'examples', height: 36, child: Text('Saved Examples')),
        if (entry.mode == 'http')
          PopupMenuItem(value: 'mock', height: 36, child: Text('Create Mock Route…')),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          height: 36,
          child: Text(
            'Delete ${entry.mode == 'ws' ? 'Connection' : 'Request'}',
            style: TextStyle(color: AstraColors.err),
          ),
        ),
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
            : BoxDecoration(
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
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AstraColors.surface2,
          border: Border.all(color: AstraColors.accent),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 12)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MethodBadge(method: method),
            SizedBox(width: 8),
            Text(name, style: TextStyle(fontSize: 11.5, color: AstraColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _historyList(AppState state) {
    final items = state.historyFor(state.mode);
    if (items.isEmpty) {
      return EmptyHint(
        icon: Icons.history_rounded,
        title: 'No history yet',
        subtitle: 'After you send a request,\nthe latest 80 entries will be kept here',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(10, 4, 10, 12),
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

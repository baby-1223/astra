import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state.dart';
import 'ui/advanced_dialogs.dart';
import 'ui/dialogs.dart';
import 'ui/http_panel.dart';
import 'ui/request_tabs.dart';
import 'ui/runner_dialog.dart';
import 'ui/sidebar.dart';
import 'ui/theme.dart';
import 'ui/top_bar.dart';
import 'ui/ws_panel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AstraApp());
}

class AstraApp extends StatefulWidget {
  final AppState? state;

  AstraApp({super.key, this.state});

  @override
  State<AstraApp> createState() => _AstraAppState();
}

class _AstraAppState extends State<AstraApp> {
  late final AppState state = widget.state ?? AppState();

  @override
  void initState() {
    super.initState();
    AstraColors.applyBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        _syncBrightness;
    if (widget.state == null) state.load();
  }

  void _syncBrightness() {
    AstraColors.applyBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    if (mounted) setState(() {});
  }

  /// 焦点在文本输入框时，不响应集合树的编辑类快捷键。
  bool get _editingText =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  Future<void> _addRequestToSelection() async {
    final folder = state.selectedFolderNode;
    if (folder != null) {
      state.newRequestIn(folder.groupId, folder.id);
      return;
    }
    final group = state.selectedGroupNode;
    if (group != null) {
      state.newRequestIn(group.id, '');
      return;
    }
    state.newRequest();
  }

  Future<void> _addFolderToSelection(BuildContext context) async {
    final group = state.selectedGroupNode ??
        state.groups
            .where((item) => item.id == (state.selectedFolderNode?.groupId ?? ''))
            .firstOrNull;
    if (group == null) return;
    final parentId = state.selectedFolderNode?.id ?? '';
    final name = await showGroupDialog(
      context,
      title: parentId.isEmpty ? 'New Folder' : 'New Subfolder',
      initial: '',
      mode: group.mode,
    );
    if (name == null || name.trim().isEmpty) return;
    state.createFolder(group.id, parentId, name);
  }

  Future<void> _addCollectionFromShortcut(BuildContext context) async {
    if (state.selectedGroupNode != null || state.selectedFolderNode != null) {
      return;
    }
    final name = await showGroupDialog(
      context,
      title: state.mode == 'ws'
          ? 'New Connection Collection'
          : 'New Request Collection',
      initial: '',
      mode: state.mode,
    );
    if (name == null || name.trim().isEmpty) return;
    state.createGroup(name, state.mode);
  }

  Future<void> _renameSelection(BuildContext context) async {
    if (_editingText) return;
    final group = state.selectedGroupNode;
    if (group != null) {
      final name = await showGroupDialog(
        context,
        title: 'Rename Collection',
        initial: group.name,
        mode: group.mode,
      );
      if (name != null) state.renameGroup(group.id, name);
      return;
    }
    final folder = state.selectedFolderNode;
    if (folder != null) {
      final mode = state.groups
              .where((item) => item.id == folder.groupId)
              .firstOrNull
              ?.mode ??
          'http';
      final name = await showGroupDialog(
        context,
        title: 'Rename Folder',
        initial: folder.name,
        mode: mode,
      );
      if (name != null) state.renameFolder(folder.id, name);
      return;
    }
    final entry = state.selectedEntryNode;
    if (entry != null) await showEntryMetaDialog(context, state, entry.id);
  }

  void _duplicateSelection() {
    if (_editingText) return;
    final group = state.selectedGroupNode;
    if (group != null) {
      final copy = state.duplicateGroup(group.id);
      if (copy != null) state.showToast('Copied as "${copy.name}"');
      return;
    }
    final folder = state.selectedFolderNode;
    if (folder != null) {
      final copy = state.duplicateFolder(folder.id);
      if (copy != null) state.showToast('Copied as "${copy.name}"');
      return;
    }
    final entry = state.selectedEntryNode;
    if (entry != null) {
      final copy = state.duplicateEntry(entry.id);
      if (copy != null) state.showToast('Copied as "${copy.name}"');
    }
  }

  Future<void> _deleteSelection(BuildContext context) async {
    if (_editingText) return;
    final group = state.selectedGroupNode;
    if (group != null) {
      final isWs = group.mode == 'ws';
      final ok = await showConfirmDialog(
        context,
        title: 'Delete Collection',
        message:
            'Deleting "${group.name}" also removes every ${isWs ? 'connection' : 'request'} and folder inside it. This cannot be undone.',
      );
      if (ok) {
        state.deleteGroup(group.id);
        state.selectTreeNode('', '');
      }
      return;
    }
    final folder = state.selectedFolderNode;
    if (folder != null) {
      final parentGroup = state.groups
          .where((item) => item.id == folder.groupId)
          .firstOrNull;
      final ok = await showConfirmDialog(
        context,
        title: 'Delete Folder',
        message:
            'Deleting "${folder.name}" also removes every ${parentGroup?.mode == 'ws' ? 'connection' : 'request'} and subfolder inside it. This cannot be undone.',
      );
      if (ok) {
        state.deleteFolder(folder.id);
        state.selectTreeNode('', '');
      }
      return;
    }
    final entry = state.selectedEntryNode;
    if (entry != null) {
      final ok = await showConfirmDialog(
        context,
        title: 'Delete ${entry.mode == 'ws' ? 'Connection' : 'Request'}',
        message: 'Delete "${entry.name}"? This cannot be undone.',
      );
      if (ok) {
        state.deleteEntry(entry.id);
        state.selectTreeNode('', '');
      }
    }
  }

  Future<void> _runSelection(BuildContext context) async {
    final folder = state.selectedFolderNode;
    if (folder != null) {
      await showRunnerDialog(
        context,
        state,
        groupId: folder.groupId,
        folderId: folder.id,
      );
      return;
    }
    final group = state.selectedGroupNode;
    if (group != null) {
      await showRunnerDialog(context, state, groupId: group.id);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged = null;
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Astra',
      debugShowCheckedModeBanner: false,
      theme: buildAstraTheme(),
      home: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          return CallbackShortcuts(
            bindings: {
              SingleActivator(LogicalKeyboardKey.keyS, meta: true): state.saveActive,
              SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  state.saveActive,
              SingleActivator(LogicalKeyboardKey.keyT, meta: true): state.newRequest,
              SingleActivator(LogicalKeyboardKey.keyT, control: true):
                  state.newRequest,
              SingleActivator(LogicalKeyboardKey.keyN, meta: true): state.newRequest,
              SingleActivator(LogicalKeyboardKey.keyN, control: true):
                  state.newRequest,
              SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
                  state.selectRelativeTab(-1),
              SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
                  state.selectRelativeTab(1),
              SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
                  state.closeTab(state.activeTabId),
              SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
                  state.closeTab(state.activeTabId),
              SingleActivator(LogicalKeyboardKey.keyV, meta: true, shift: true): () =>
                  showVariablesDialog(context, state),
              SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
                  () => showVariablesDialog(context, state),
              SingleActivator(LogicalKeyboardKey.keyR, meta: true, shift: true): () =>
                  showRunnerDialog(context, state),
              SingleActivator(LogicalKeyboardKey.keyR, control: true, shift: true):
                  () => showRunnerDialog(context, state),
              SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                  showShortcutsDialog(context),
              SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                  showShortcutsDialog(context),
              SingleActivator(LogicalKeyboardKey.slash, meta: true): () =>
                  showShortcutsDialog(context),
              SingleActivator(LogicalKeyboardKey.slash, control: true): () =>
                  showShortcutsDialog(context),
              SingleActivator(LogicalKeyboardKey.f2): () =>
                  _renameSelection(context),
              SingleActivator(LogicalKeyboardKey.keyD, meta: true):
                  _duplicateSelection,
              SingleActivator(LogicalKeyboardKey.keyD, control: true):
                  _duplicateSelection,
              SingleActivator(LogicalKeyboardKey.delete): () =>
                  _deleteSelection(context),
              SingleActivator(LogicalKeyboardKey.backspace): () =>
                  _deleteSelection(context),
              SingleActivator(LogicalKeyboardKey.keyR, meta: true, alt: true):
                  _addRequestToSelection,
              SingleActivator(LogicalKeyboardKey.keyR, control: true, alt: true):
                  _addRequestToSelection,
              SingleActivator(LogicalKeyboardKey.keyF, meta: true, alt: true):
                  () => _addFolderToSelection(context),
              SingleActivator(LogicalKeyboardKey.keyF, control: true, alt: true):
                  () => _addFolderToSelection(context),
              SingleActivator(LogicalKeyboardKey.keyC, meta: true, alt: true):
                  () => _addCollectionFromShortcut(context),
              SingleActivator(LogicalKeyboardKey.keyC, control: true, alt: true):
                  () => _addCollectionFromShortcut(context),
              SingleActivator(LogicalKeyboardKey.enter, meta: true, shift: true):
                  () => _runSelection(context),
              SingleActivator(LogicalKeyboardKey.enter, control: true, shift: true):
                  () => _runSelection(context),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                backgroundColor: AstraColors.bg,
                body: Stack(
                  children: [
                    Column(
                      children: [
                        TopBar(state: state),
                        Expanded(
                          child: Row(
                            children: [
                              Sidebar(state: state),
                              Expanded(
                                child: Column(
                                  children: [
                                    RequestTabBar(state: state),
                                    Expanded(
                                      child: state.mode == 'ws'
                                          ? WsView(state: state)
                                          : HttpView(state: state),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (state.toast != null)
                      Positioned(
                        bottom: 26,
                        left: 0,
                        right: 0,
                        child: Center(child: _Toast(message: state.toast!)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  final String message;

  _Toast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 640),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AstraColors.surface2,
        border: Border.all(color: AstraColors.accentBorder),
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(color: Color(0x73000000), blurRadius: 30, offset: Offset(0, 10)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 15, color: AstraColors.accent),
          SizedBox(width: 9),
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AstraColors.text, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

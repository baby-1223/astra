import 'package:astra/main.dart';
import 'package:astra/models.dart';
import 'package:astra/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpApp(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1360, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AstraApp(state: state));
  await tester.pump(const Duration(milliseconds: 200));
}

/// Press a key with optional modifiers held, mirroring the IDEA plugin's
/// Ctrl/Cmd + Alt + Shift accelerators.
Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool control = false,
  bool alt = false,
  bool shift = false,
}) async {
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

AppState _seedState() {
  final state = AppState();
  final group = state.createGroup('Demo Group', 'http');
  state.createFolder(group.id, '', 'Demo Folder');
  state.collections.add(CollectionEntry(
    name: 'List users',
    groupId: group.id,
    mode: 'http',
    request: ApiRequest(method: 'GET', url: 'https://api.example.com/users'),
  ));
  return state;
}

/// Widget-test harness: seeds a workspace, pumps the app, runs [body], then
/// flushes the persist/draft debounce timers so they are not left pending.
void _treeTest(
  String name,
  Future<void> Function(WidgetTester tester, AppState state) body,
) {
  testWidgets(name, (tester) async {
    final state = _seedState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);
    await body(tester, state);
    // Let debounce timers (state persist 400 ms + storage timeout 800 ms)
    // fire before the binding checks invariants at teardown.
    await tester.pump(const Duration(seconds: 3));
  });
}

void main() {
  group('AppState tree selection', () {
    test('selectTreeNode resolves group / folder / entry nodes', () {
      final state = _seedState();
      addTearDown(state.dispose);
      final group = state.groups.single;
      final folder = state.folders.single;
      final entry = state.collections.single;

      state.selectTreeNode('group', group.id);
      expect(state.selectedGroupNode, group);
      expect(state.selectedFolderNode, isNull);
      expect(state.selectedEntryNode, isNull);

      state.selectTreeNode('folder', folder.id);
      expect(state.selectedFolderNode, folder);

      state.selectTreeNode('entry', entry.id);
      expect(state.selectedEntryNode, entry);
    });

    test('getters return null for stale / unknown ids', () {
      final state = _seedState();
      addTearDown(state.dispose);
      state.selectTreeNode('group', 'does-not-exist');
      expect(state.selectedGroupNode, isNull);

      state.selectTreeNode('', '');
      expect(state.selectedNodeKind, isEmpty);
      expect(state.selectedGroupNode, isNull);
      expect(state.selectedFolderNode, isNull);
      expect(state.selectedEntryNode, isNull);
    });
  });

  group('Tree keyboard shortcuts', () {
    _treeTest('tapping a collection header marks it selected', (tester, state) async {
      await tester.tap(find.text('Demo Group'));
      await tester.pump();
      expect(state.selectedNodeKind, 'group');
      expect(state.selectedNodeId, state.groups.single.id);
    });

    _treeTest('F2 opens Rename Collection for a selected group', (tester, state) async {
      state.selectTreeNode('group', state.groups.single.id);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.f2);
      expect(find.text('Rename Collection'), findsOneWidget);
    });

    _treeTest('F2 opens Rename Folder for a selected folder', (tester, state) async {
      state.selectTreeNode('folder', state.folders.single.id);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.f2);
      expect(find.text('Rename Folder'), findsOneWidget);
    });

    _treeTest('F2 opens Request Info for a selected entry', (tester, state) async {
      state.selectTreeNode('entry', state.collections.single.id);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.f2);
      expect(find.text('Request Info'), findsOneWidget);
    });

    _treeTest('Cmd+D duplicates the selected group', (tester, state) async {
      state.selectTreeNode('group', state.groups.single.id);
      await tester.pump();
      final before = state.groups.length;
      await _press(tester, LogicalKeyboardKey.keyD, meta: true);
      expect(state.groups.length, before + 1);
      expect(state.toast, contains('Copied as'));
    });

    _treeTest('Cmd+D duplicates the selected folder', (tester, state) async {
      state.selectTreeNode('folder', state.folders.single.id);
      await tester.pump();
      final before = state.folders.length;
      await _press(tester, LogicalKeyboardKey.keyD, meta: true);
      expect(state.folders.length, before + 1);
    });

    _treeTest('Ctrl+D duplicates the selected entry (Windows variant)',
        (tester, state) async {
      state.selectTreeNode('entry', state.collections.single.id);
      await tester.pump();
      final before = state.collections.length;
      await _press(tester, LogicalKeyboardKey.keyD, control: true);
      expect(state.collections.length, before + 1);
    });

    _treeTest('Delete confirms and removes the selected group', (tester, state) async {
      state.selectTreeNode('group', state.groups.single.id);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.delete);
      expect(find.text('Delete Collection'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(state.groups, isEmpty);
      expect(state.selectedNodeKind, isEmpty);
    });

    _treeTest('Backspace confirms and removes the selected entry',
        (tester, state) async {
      state.selectTreeNode('entry', state.collections.single.id);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.backspace);
      expect(find.text('Delete Request'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(state.collections, isEmpty);
      expect(state.selectedNodeKind, isEmpty);
    });

    _treeTest('Alt+Cmd+R adds a request inside the selected folder',
        (tester, state) async {
      final folder = state.folders.single;
      state.selectTreeNode('folder', folder.id);
      await tester.pump();
      final before = state.tabs.length;
      await _press(tester, LogicalKeyboardKey.keyR, meta: true, alt: true);
      expect(state.tabs.length, before + 1);
      expect(state.tabs.last.groupId, folder.groupId);
      expect(state.tabs.last.folderId, folder.id);
    });

    _treeTest('Alt+Cmd+F opens New Folder inside the selected group',
        (tester, state) async {
      state.selectTreeNode('group', state.groups.single.id);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.keyF, meta: true, alt: true);
      expect(find.text('New Folder'), findsOneWidget);
    });

    _treeTest('Alt+Cmd+C opens New Collection when nothing is selected',
        (tester, state) async {
      await _press(tester, LogicalKeyboardKey.keyC, meta: true, alt: true);
      expect(find.text('New Request Collection'), findsOneWidget);
    });

    _treeTest('Alt+Cmd+C does nothing when a group is selected',
        (tester, state) async {
      state.selectTreeNode('group', state.groups.single.id);
      await tester.pump();
      final before = state.groups.length;
      await _press(tester, LogicalKeyboardKey.keyC, meta: true, alt: true);
      expect(find.text('New Request Collection'), findsNothing);
      expect(state.groups.length, before);
    });

    _treeTest('Cmd+Shift+Enter runs the selected collection', (tester, state) async {
      state.selectTreeNode('group', state.groups.single.id);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.enter, meta: true, shift: true);
      expect(find.text('Run Demo Group'), findsOneWidget);
    });

    _treeTest('editing shortcuts are suppressed while a text field is focused',
        (tester, state) async {
      state.newRequest();
      await tester.pump();
      state.selectTreeNode('group', state.groups.single.id);
      await tester.pump();
      final before = state.groups.length;
      await tester.tap(find.byKey(const ValueKey('active-name')));
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.keyD, meta: true);
      expect(state.groups.length, before);
    });
  });
}

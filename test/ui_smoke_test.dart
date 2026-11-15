import 'dart:convert';

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

void main() {
  testWidgets('主界面在桌面尺寸下正常渲染且无溢出', (tester) async {
    final state = AppState();
    await _pumpApp(tester, state);

    expect(find.text('ASTRA'), findsOneWidget);
    expect(find.text('发送'), findsWidgets);
    expect(find.text('响应'), findsWidgets);
    expect(find.text('集合'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('响应面板展示状态与 JSON 内容', (tester) async {
    final state = AppState();
    final bytes = Uint8List.fromList(utf8.encode('{"ok":true,"name":"Astra"}'));
    state.response = HttpResult(
      status: 200,
      reason: 'OK',
      headers: {
        'content-type': ['application/json'],
      },
      bytes: bytes,
      text: '{"ok":true,"name":"Astra"}',
      ms: 42,
      size: bytes.length,
    );
    await _pumpApp(tester, state);

    expect(find.textContaining('200 OK'), findsOneWidget);
    expect(find.textContaining('42 ms'), findsOneWidget);
    // 默认树形视图
    expect(find.text('树形'), findsOneWidget);
    expect(find.text('文本'), findsOneWidget);
    expect(find.text('全部展开'), findsOneWidget);

    // 切到文本视图后显示格式化后的 JSON
    await tester.tap(find.text('文本'));
    await tester.pump();
    expect(find.textContaining('"name": "Astra"'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WebSocket 视图正常渲染', (tester) async {
    final state = AppState()..mode = 'ws';
    state.wsLog.add(WsMessage('连接已建立', system: true));
    state.wsLog.add(WsMessage('{"type":"ping"}', outgoing: true));
    state.wsLog.add(WsMessage('{"type":"pong"}'));
    await _pumpApp(tester, state);

    expect(find.text('WebSocket 连接'), findsOneWidget);
    expect(find.text('消息记录'), findsOneWidget);
    expect(find.text('未连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('集合分组与连接集合正常渲染', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);

    final group = state.createGroup('用户服务', 'http');
    state.request = ApiRequest(url: 'https://api.demo.com/users');
    state.saveCurrent('用户列表', groupId: group.id);
    final wsGroup = state.createGroup('实时通道', 'ws');
    state.collections.add(CollectionEntry(
      name: '本地回显',
      mode: 'ws',
      groupId: wsGroup.id,
      ws: WsConfig(url: 'ws://127.0.0.1:8080/ws'),
    ));

    await _pumpApp(tester, state);

    expect(find.text('用户服务'), findsOneWidget);
    expect(find.text('用户列表'), findsWidgets);
    expect(find.text('新建集合'), findsOneWidget);
    expect(tester.takeException(), isNull);

    state.switchMode('ws');
    await tester.pump();

    expect(find.text('实时通道'), findsOneWidget);
    expect(find.text('本地回显'), findsOneWidget);
    expect(find.text('新建连接集合'), findsOneWidget);
    expect(find.text('用户服务'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('集合内多级文件夹树渲染并提供新建 API 入口', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);

    final group = state.createGroup('后台服务', 'http');
    final folder = state.createFolder(group.id, '', '管理端');
    state.createFolder(group.id, folder.id, '用户管理');
    state.request = ApiRequest(url: 'https://api.demo.com/users');
    state.saveCurrent('用户列表', groupId: group.id, folderId: folder.id);

    await _pumpApp(tester, state);

    expect(find.text('后台服务'), findsOneWidget);
    expect(find.text('管理端'), findsOneWidget);
    expect(find.text('用户管理'), findsOneWidget);
    expect(find.text('用户列表'), findsWidgets);

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    expect(find.text('新建请求'), findsWidgets);
    expect(find.text('新建文件夹'), findsOneWidget);

    await tester.tap(find.text('新建请求').last);
    await tester.pumpAndSettle();
    expect(find.text('未命名 API（草稿）'), findsOneWidget);
    expect(find.text('未命名 API'), findsNWidgets(2));

    state.saveCurrent('新接口');
    await tester.pump();
    expect(find.text('新接口'), findsWidgets);
    expect(find.text('未命名 API（草稿）'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_horiz).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建请求').last);
    await tester.pumpAndSettle();
    expect(find.text('未命名 API（草稿）'), findsOneWidget);
    expect(state.pendingFolderId, folder.id);

    state.saveCurrent('文件夹接口');
    await tester.pump();
    expect(find.text('文件夹接口'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('新建 API 会在右侧新增标签页', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    final group = state.createGroup('用户服务', 'http');
    final folder = state.createFolder(group.id, '', '管理端');
    await _pumpApp(tester, state);
    expect(state.tabs, isEmpty);

    state.newRequestIn(group.id, folder.id);
    await tester.pump();
    expect(state.tabs.length, 1);
    expect(state.tabs.single.groupId, group.id);
    expect(state.tabs.single.folderId, folder.id);
    expect(find.text('未命名 API'), findsNWidgets(2));

    await tester.enterText(find.byKey(const ValueKey('active-name')), '用户详情');
    await tester.pump();
    expect(state.tabs.single.name, '用户详情');

    state.request.url = 'https://api.demo.com/users/1';
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(state.collections.single.name, '用户详情');
    expect(state.tabs.single.entryId, state.collections.single.id);
    expect(find.text('保存'), findsNothing);

    state.newRequestIn(group.id, '');
    await tester.pump();
    expect(state.tabs.length, 2);
    expect(find.text('用户详情'), findsWidgets);

    await tester.tap(find.text('用户详情').first);
    await tester.pump();
    expect(state.activeTabId, state.tabs.first.id);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('较小窗口下请求与响应区域无溢出', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    final bytes = Uint8List.fromList(utf8.encode('{"items":[1,2,3],"ok":true}'));
    state.request = ApiRequest(url: 'https://api.demo.com/items');
    state.response = HttpResult(
      status: 200,
      reason: 'OK',
      headers: {
        'content-type': ['application/json'],
      },
      bytes: bytes,
      text: '{"items":[1,2,3],"ok":true}',
      ms: 18,
      size: bytes.length,
    );

    tester.view.physicalSize = const Size(1080, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AstraApp(state: state));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('发送'), findsWidgets);
    expect(find.text('全部展开'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('图片响应展示预览与保存入口', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    final bytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));
    state.response = HttpResult(
      status: 200,
      reason: 'OK',
      headers: {
        'content-type': ['image/png'],
      },
      bytes: bytes,
      text: null,
      ms: 8,
      size: bytes.length,
    );
    await _pumpApp(tester, state);

    expect(find.text('图片预览'), findsOneWidget);
    expect(find.text('适应窗口'), findsOneWidget);
    expect(find.text('原始尺寸'), findsOneWidget);
    expect(find.text('保存图片'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('二进制响应展示占位卡片与保存按钮', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    final bytes = Uint8List.fromList([0, 1, 2, 3, 4]);
    state.response = HttpResult(
      status: 200,
      reason: 'OK',
      headers: {
        'content-type': ['application/pdf'],
      },
      bytes: bytes,
      text: null,
      ms: 6,
      size: bytes.length,
    );
    await _pumpApp(tester, state);

    expect(find.text('二进制响应'), findsOneWidget);
    expect(find.textContaining('application/pdf'), findsWidgets);
    expect(find.text('保存到本地'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('环境切换菜单列出全部环境', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    state.createEnv('开发');
    state.createEnv('生产');

    await _pumpApp(tester, state);

    expect(find.text('生产'), findsOneWidget);
    await tester.tap(find.text('生产'));
    await tester.pumpAndSettle();

    expect(find.text('管理环境…'), findsOneWidget);
    expect(find.text('开发'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });
}

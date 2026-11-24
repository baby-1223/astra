import 'dart:io';

import 'package:astra/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Storage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('astra-storage-test');
    storage = Storage(root: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('Storage', () {
    test('写入后可读取，缺失文件返回 null', () async {
      expect(await storage.read('workspace.json'), isNull);
      expect(await storage.write('workspace.json', {'a': 1}), isTrue);
      expect((await storage.read('workspace.json'))!['a'], 1);
    });

    test('新写入保留上一份备份', () async {
      await storage.write('workspace.json', {'v': 1});
      await storage.write('workspace.json', {'v': 2});

      final file = File('${tempDir.path}${Platform.pathSeparator}workspace.json.bak');
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), contains('"v":1'));
    });

    test('主文件损坏时回退到备份并触发回调', () async {
      await storage.write('workspace.json', {'v': 1});
      await storage.write('workspace.json', {'v': 2});
      // 主文件写成非法 JSON，模拟写入中断
      await File('${tempDir.path}${Platform.pathSeparator}workspace.json')
          .writeAsString('{broken');

      final notices = <String>[];
      storage.onRecovered = notices.add;
      final data = await storage.read('workspace.json');

      expect(data!['v'], 1);
      expect(notices, isNotEmpty);
    });

    test('空文件视为不存在', () async {
      await File('${tempDir.path}${Platform.pathSeparator}workspace.json')
          .writeAsString('   ');
      expect(await storage.read('workspace.json'), isNull);
    });

    test('delete 清理主文件与全部备份', () async {
      await storage.write('workspace.json', {'v': 1});
      await storage.write('workspace.json', {'v': 2});
      await storage.delete('workspace.json');

      expect(await storage.read('workspace.json'), isNull);
      expect(
        await File('${tempDir.path}${Platform.pathSeparator}workspace.json.bak').exists(),
        isFalse,
      );
    });

    test('directory 返回可写目录并复用一个实例', () async {
      final first = await storage.directory();
      final second = await storage.directory();
      expect(first.path, tempDir.path);
      expect(identical(first, second), isTrue);
    });
  });
}

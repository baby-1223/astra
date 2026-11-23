import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Storage {
  Directory? _dir;

  Future<Directory> _root() async {
    if (_dir != null) return _dir!;
    Directory dir;
    try {
      final support = await getApplicationSupportDirectory()
          .timeout(const Duration(milliseconds: 800));
      dir = Directory('${support.path}${Platform.pathSeparator}Astra');
    } catch (_) {
      dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}Astra');
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<Map<String, dynamic>?> read(String name) async {
    try {
      final dir = await _root();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      final data = jsonDecode(text);
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String name, Map<String, dynamic> data) async {
    try {
      final dir = await _root();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // 持久化失败不阻断主流程。
    }
  }

  /// 删除持久化文件；文件不存在时静默忽略。
  Future<void> delete(String name) async {
    try {
      final dir = await _root();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删除失败不阻断主流程。
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef StorageNotice = void Function(String message);

class Storage {
  Storage({this.onError, this.onRecovered});

  /// 持久化失败时回调，用于向用户提示，避免静默丢数据。
  StorageNotice? onError;

  /// 主文件损坏、从备份恢复时回调。
  StorageNotice? onRecovered;

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
    final dir = await _root();
    for (final candidate in ['$name', '$name.bak', '$name.bak1']) {
      final data = await _readFile(File('${dir.path}${Platform.pathSeparator}$candidate'));
      if (data != null) {
        if (candidate != name) {
          onRecovered?.call('$name 已损坏，已从备份恢复');
        }
        return data;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _readFile(File file) async {
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      final data = jsonDecode(text);
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> write(String name, Map<String, dynamic> data) async {
    try {
      final dir = await _root();
      final path = '${dir.path}${Platform.pathSeparator}$name';
      final file = File(path);
      final backup = File('$path.bak');
      final older = File('$path.bak1');
      if (await file.exists()) {
        if (await older.exists()) await older.delete();
        if (await backup.exists()) await backup.rename(older.path);
        await file.rename(backup.path);
      }
      final temp = File('$path.tmp');
      await temp.writeAsString(jsonEncode(data), flush: true);
      await temp.rename(path);
      return true;
    } catch (error) {
      onError?.call('保存 $name 失败：$error');
      return false;
    }
  }

  /// 删除持久化文件及其备份；文件不存在时静默忽略。
  Future<void> delete(String name) async {
    try {
      final dir = await _root();
      for (final suffix in ['', '.bak', '.bak1', '.tmp']) {
        final file = File('${dir.path}${Platform.pathSeparator}$name$suffix');
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // 删除失败不阻断主流程。
    }
  }
}

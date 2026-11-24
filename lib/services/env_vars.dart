import '../models.dart';

/// 解析粘贴的 `.env`（KEY=VALUE）或 CSV（两列：key,value）文本为变量行。
///
/// - 以 `#` 开头的行与空行会被忽略；
/// - `.env` 支持 `export KEY=VALUE`、单/双引号包裹的值；
/// - CSV 支持带引号的字段，首行若为 `key,value` / `name,value` 等表头会自动跳过。
List<KV> parseVariableText(String text) {
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
  if (lines.isEmpty) return const [];
  final first = lines.first;
  final looksCsv = first.contains(',') && !first.contains('=');
  return looksCsv ? _parseCsv(lines) : _parseDotEnv(lines);
}

List<KV> _parseDotEnv(List<String> lines) {
  final result = <KV>[];
  for (final raw in lines) {
    var line = raw;
    if (line.startsWith('export ')) line = line.substring(7).trim();
    final index = line.indexOf('=');
    if (index <= 0) continue;
    final key = line.substring(0, index).trim();
    if (key.isEmpty) continue;
    var value = line.substring(index + 1).trim();
    if (value.length >= 2) {
      final quoted = (value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"));
      if (quoted) {
        final quote = value[0];
        value = value.substring(1, value.length - 1);
        if (quote == '"') {
          value = value
              .replaceAll(r'\n', '\n')
              .replaceAll(r'\r', '\r')
              .replaceAll(r'\t', '\t')
              .replaceAll(r'\"', '"')
              .replaceAll(r'\\', r'\');
        }
      }
    }
    result.add(KV(on: true, k: key, v: value));
  }
  return result;
}

List<KV> _parseCsv(List<String> lines) {
  var start = 0;
  final header = _csvFields(lines.first).map((cell) => cell.toLowerCase()).toList();
  if (header.length >= 2 &&
      const ['key', 'name', 'variable', 'variable name'].contains(header[0])) {
    start = 1;
  }
  final result = <KV>[];
  for (var i = start; i < lines.length; i++) {
    final fields = _csvFields(lines[i]);
    if (fields.isEmpty) continue;
    final key = fields[0].trim();
    if (key.isEmpty) continue;
    final value = fields.length > 1 ? fields[1].trim() : '';
    result.add(KV(on: true, k: key, v: value));
  }
  return result;
}

/// 最小 CSV 解析：支持逗号分隔和双引号包裹（`""` 表示转义的引号）。
List<String> _csvFields(String line) {
  final fields = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  var index = 0;
  while (index < line.length) {
    final char = line[index];
    if (quoted) {
      if (char == '"') {
        if (index + 1 < line.length && line[index + 1] == '"') {
          buffer.write('"');
          index += 2;
          continue;
        }
        quoted = false;
      } else {
        buffer.write(char);
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      fields.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
    index++;
  }
  fields.add(buffer.toString());
  return fields;
}

/// 把变量行渲染为 `.env` 文本，必要时用双引号包裹并转义。
String toDotEnv(Iterable<KV> rows) {
  final out = StringBuffer();
  for (final row in rows) {
    final key = row.k.trim();
    if (key.isEmpty) continue;
    out.writeln('$key=${_envValue(row.v)}');
  }
  return out.toString();
}

String _envValue(String value) {
  if (value.isEmpty) return '';
  if (!RegExp(r'''[\s#'"\\]''').hasMatch(value)) return value;
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models.dart';

const Map<String, String> _mimeTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'pdf': 'application/pdf',
  'json': 'application/json',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'xml': 'application/xml',
  'html': 'text/html',
  'zip': 'application/zip',
  'gz': 'application/gzip',
  'mp3': 'audio/mpeg',
  'mp4': 'video/mp4',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

String mimeFor(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final index = name.lastIndexOf('.');
  if (index < 0) return 'application/octet-stream';
  return _mimeTypes[name.substring(index + 1).toLowerCase()] ?? 'application/octet-stream';
}

class PickedJson {
  final String fileName;
  final Map<String, dynamic> data;

  PickedJson(this.fileName, this.data);
}

/// 选择并解析 JSON 文件；返回 null 表示用户取消。
Future<PickedJson?> pickJsonFile() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Select Import File',
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (file == null) return null;

  final bytes = await file.readAsBytes().catchError((err) {
    throw FormatException('Unable to read the selected file. Make sure it is accessible and try again ($err)');
  });
  final text = utf8.decode(bytes, allowMalformed: true);
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('{')) {
    throw const FormatException('YAML and other non-JSON files are not supported. Convert to JSON before importing');
  }
  dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } catch (err) {
    throw FormatException('Failed to parse JSON: $err');
  }
  if (decoded is! Map) {
    throw const FormatException('File content is not a valid object structure');
  }
  return PickedJson(file.name, Map<String, dynamic>.from(decoded));
}

/// 保存 JSON 文件；返回保存路径，取消时返回 null。
Future<String?> saveJsonFile(String suggestedName, Map<String, dynamic> data) async {
  final bytes = Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
  );
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Export',
    fileName: suggestedName,
    mimeType: 'application/json',
    bytes: bytes,
  );
  if (uri == null) return null;
  if (uri.scheme == 'file') return uri.toFilePath();
  return '$uri';
}

/// 保存任意二进制内容（响应体下载）；返回保存路径，取消时返回 null。
Future<String?> saveBytesFile(String suggestedName, Uint8List bytes, String mime) async {
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Save Response Body',
    fileName: suggestedName,
    mimeType: mime,
    bytes: bytes,
  );
  if (uri == null) return null;
  if (uri.scheme == 'file') return uri.toFilePath();
  return '$uri';
}

/// 选择 multipart 上传文件。
Future<UploadFile?> pickUploadFile() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Select Upload File',
    type: FileType.any,
  );
  if (file == null) return null;

  var path = file.path;
  final size = await file.length() ?? 0;
  if (path == null || path.isEmpty) {
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}astra_uploads');
    if (!await dir.exists()) await dir.create(recursive: true);
    final target = File('${dir.path}${Platform.pathSeparator}${file.name}');
    await target.writeAsBytes(await file.readAsBytes(), flush: true);
    path = target.path;
  }

  return UploadFile(
    name: file.name,
    path: path,
    mime: mimeFor(file.name),
    size: size,
  );
}

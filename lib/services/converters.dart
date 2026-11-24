import 'dart:convert';

import '../models.dart';

part 'converters/shared.dart';
part 'converters/postman_import.dart';
part 'converters/postman_export.dart';
part 'converters/openapi_import.dart';
part 'converters/openapi_export.dart';

class ImportResult {
  final List<CollectionEntry> collections;
  final List<KV> variables;
  final String name;
  final List<Env> environments;
  final List<KV> globals;
  final List<CollectionGroup> groups;
  final List<CollectionFolder> folders;

  ImportResult({
    required this.collections,
    required this.variables,
    required this.name,
    this.environments = const [],
    this.globals = const [],
    this.groups = const [],
    this.folders = const [],
  });
}

import 'dart:convert';

import '../models.dart';

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

List<KV> _kvList(dynamic list) => _list(list)
    .whereType<Map>()
    .where((item) =>
        _str(item['key']).trim().isNotEmpty &&
        item['disabled'] != true &&
        item['enabled'] != false)
    .map((item) => KV(k: _str(item['key']).trim(), v: _str(item['value'])))
    .toList();

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> _list(dynamic value) => value is List ? value : const [];

String _str(dynamic value) => value == null ? '' : '$value';

Map<String, dynamic> _emptyRequest() => {
      'method': 'GET',
      'url': '',
      'params': <dynamic>[],
      'headers': <dynamic>[],
      'bodyMode': 'none',
      'body': '',
      'form': <dynamic>[],
      'formData': <dynamic>[],
    };

bool _isPostmanDump(Map data) {
  final raw = data['collections'];
  if (raw is! List) return false;
  if (raw.isEmpty) return data['environments'] is List;
  for (final entry in raw.whereType<Map>()) {
    if (entry['item'] is List ||
        entry['info'] is Map ||
        entry['requests'] is List ||
        entry['folders'] is List) {
      return true;
    }
  }
  return false;
}

String detectKind(dynamic data) {
  if (data is! Map) return 'unknown';
  if (_isPostmanDump(data)) return 'postman';
  if (data['collections'] is List) return 'astra';
  if (data['openapi'] != null || data['swagger'] != null) return 'openapi';
  if (data['info'] is Map &&
      ((data['info'] as Map)['schema'] != null ||
          (data['info'] as Map)['_postman_id'] != null ||
          (data['info'] as Map)['item'] is List)) {
    return 'postman';
  }
  if (data['item'] is List) return 'postman';
  return 'unknown';
}

CollectionEntry _collection(
  String name,
  Map<String, dynamic> request, {
  String mode = 'http',
  WsConfig? ws,
}) {
  return CollectionEntry(
    name: name,
    mode: mode,
    request: mode == 'http' ? ApiRequest.fromJson(request) : null,
    ws: ws,
  );
}

/* ------------------------------------------------------------------ */
/* Postman v2.0 / v2.1                                                */
/* ------------------------------------------------------------------ */

String _postmanUrl(dynamic url) {
  if (url is String) return url;
  final value = _map(url);
  if (value.isEmpty) return '';
  if (_str(value['raw']).isNotEmpty) return _str(value['raw']);
  final protocol = _str(value['protocol']).isEmpty ? '' : '${value['protocol']}://';
  final host = value['host'] is List ? (value['host'] as List).join('.') : _str(value['host']);
  final port = _str(value['port']).isEmpty ? '' : ':${value['port']}';
  var path = value['path'] is List ? '/${(value['path'] as List).join('/')}' : _str(value['path']);
  if (path.isNotEmpty && !path.startsWith('/')) path = '/$path';
  final query = _list(value['query'])
      .whereType<Map>()
      .where((q) => q['disabled'] != true && _str(q['key']).isNotEmpty)
      .map((q) =>
          '${Uri.encodeQueryComponent(_str(q['key']))}=${Uri.encodeQueryComponent(_str(q['value']))}')
      .join('&');
  return '$protocol$host$port$path${query.isEmpty ? '' : '?$query'}';
}

Map<String, dynamic> _postmanBody(Map<String, dynamic> body) {
  final mode = _str(body['mode']);
  if (mode.isEmpty) return {};
  if (mode == 'raw') {
    final options = _map(body['options']);
    final rawOptions = _map(options['raw']);
    final language = _str(rawOptions['language']);
    final text = _str(body['raw']);
    final isJson = language == 'json' || RegExp(r'^\s*[\[{]').hasMatch(text);
    return {'bodyMode': isJson ? 'json' : 'text', 'body': text};
  }
  if (mode == 'urlencoded') {
    return {
      'bodyMode': 'form',
      'form': _list(body['urlencoded'])
          .whereType<Map>()
          .map((item) => {
                'on': item['disabled'] != true,
                'k': _str(item['key']),
                'v': _str(item['value']),
              })
          .toList(),
    };
  }
  if (mode == 'formdata') {
    return {
      'bodyMode': 'form-data',
      'formData': _list(body['formdata']).whereType<Map>().map((item) {
        if (item['type'] == 'file') {
          final src = _str(item['src']);
          final segments = src.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
          final name = segments.isEmpty ? 'file' : segments.last;
          return {
            'on': item['disabled'] != true,
            'k': _str(item['key']).isEmpty ? 'file' : _str(item['key']),
            'v': '',
            'type': 'file',
            'file': {
              'name': name,
              'type': 'application/octet-stream',
              'size': 0,
              'path': '',
              'stale': true,
            },
          };
        }
        return {
          'on': item['disabled'] != true,
          'k': _str(item['key']),
          'v': _str(item['value']),
          'type': 'text',
        };
      }).toList(),
    };
  }
  if (mode == 'graphql') {
    final graphql = _map(body['graphql']);
    dynamic variables;
    try {
      variables = jsonDecode(_str(graphql['variables']).isEmpty ? '{}' : _str(graphql['variables']));
    } catch (_) {
      variables = <String, dynamic>{};
    }
    return {
      'bodyMode': 'json',
      'body': const JsonEncoder.withIndent('  ')
          .convert({'query': _str(graphql['query']), 'variables': variables}),
    };
  }
  return {};
}

Map<String, dynamic> _postmanAuth(
  Map<String, dynamic> auth,
  List<Map<String, dynamic>> headers,
  List<Map<String, dynamic>> params,
) {
  final result = {
    'type': 'none',
    'token': '',
    'username': '',
    'password': '',
  };
  final type = _str(auth['type']);
  if (type.isEmpty || type == 'noauth' || type == 'inherit') return result;
  final list = _list(auth[type]).whereType<Map>().toList();
  String pick(String key) {
    for (final entry in list) {
      if (_str(entry['key']) == key) return _str(entry['value']);
    }
    return '';
  }

  if (type == 'bearer') {
    result['type'] = 'bearer';
    result['token'] = pick('token');
  } else if (type == 'basic') {
    result['type'] = 'basic';
    result['username'] = pick('username');
    result['password'] = pick('password');
  } else if (type == 'apikey') {
    final key = pick('key');
    final value = pick('value');
    if (key.isEmpty) return result;
    if (pick('in') == 'query') {
      params.add({'on': true, 'k': key, 'v': value});
    } else {
      headers.add({'on': true, 'k': key, 'v': value});
    }
  } else if (type == 'oauth2') {
    final token = pick('accessToken').isNotEmpty ? pick('accessToken') : pick('token');
    if (token.isNotEmpty) {
      result['type'] = 'bearer';
      result['token'] = token;
    }
  }
  return result;
}

CollectionEntry? _postmanEntry(String name, Map raw) {
  if (raw['request'] == null) return null;
  final source = raw['request'] is String
      ? <String, dynamic>{'url': raw['request']}
      : _map(raw['request']);
  final headers = _list(source['header'])
      .whereType<Map>()
      .where((h) => _str(h['key']).isNotEmpty && h['disabled'] != true)
      .map((h) {
    final value = h['value'];
    return {
      'on': true,
      'k': _str(h['key']),
      'v': value is List ? value.map(_str).join(', ') : _str(value),
    };
  }).toList();
  final params = <Map<String, dynamic>>[];
  final auth = _postmanAuth(_map(source['auth']), headers, params);

  return _collection(name, {
    'method': _str(source['method']).isEmpty ? 'GET' : _str(source['method']).toUpperCase(),
    'url': _postmanUrl(source['url']),
    'headers': headers,
    'params': params,
    'auth': auth,
    ..._postmanBody(_map(source['body'])),
  });
}

void _walkPostmanItems(
  dynamic items,
  String prefix,
  List<CollectionEntry> collections,
  void Function(dynamic) addVars,
) {
  for (final raw in _list(items).whereType<Map>()) {
    addVars(raw['variable']);
    final name = _str(raw['name']).trim().isEmpty ? 'Untitled Request' : _str(raw['name']).trim();
    final fullName = prefix.isEmpty ? name : '$prefix / $name';
    if (raw['item'] is List) {
      _walkPostmanItems(raw['item'], fullName, collections, addVars);
      continue;
    }
    final entry = _postmanEntry(fullName, raw);
    if (entry != null) collections.add(entry);
  }
}

/// Walks a v2.1 collection inside a data dump, recreating its folder tree.
void _walkDumpItems(
  dynamic items,
  CollectionGroup group,
  String parentFolderId,
  List<CollectionEntry> collections,
  List<CollectionFolder> folders,
) {
  for (final raw in _list(items).whereType<Map>()) {
    final name = _str(raw['name']).trim().isEmpty ? 'Untitled' : _str(raw['name']).trim();
    if (raw['item'] is List) {
      final folder = CollectionFolder(
        groupId: group.id,
        parentId: parentFolderId,
        name: name,
        variables: _kvList(raw['variable']),
      );
      folders.add(folder);
      _walkDumpItems(raw['item'], group, folder.id, collections, folders);
      continue;
    }
    final entry = _postmanEntry(name, raw);
    if (entry == null) continue;
    entry
      ..groupId = group.id
      ..folderId = parentFolderId;
    collections.add(entry);
  }
}

/// Walks a legacy dump collection.
///
/// Dumps may nest requests inside folders, keep them flat with a "folder" id,
/// or only list them in a folder's "order" array. All three shapes are handled.
void _walkLegacyDumpCollection(
  Map<dynamic, dynamic> collection,
  CollectionGroup group,
  List<CollectionEntry> collections,
  List<CollectionFolder> folders,
) {
  final folderById = <String, CollectionFolder>{};
  final rawById = <String, Map>{};
  final parentOf = <String, String>{};
  final orderOf = <String, List<String>>{};
  final nestedRequestIds = <String>{};

  List<String> readOrder(dynamic raw) =>
      _list(raw).map(_str).where((id) => id.isNotEmpty).toList();

  void registerFolder(Map raw, String? nestedParentId) {
    var id = _str(raw['id']).trim();
    if (id.isEmpty) id = 'folder-${folderById.length}';
    if (folderById.containsKey(id)) return;
    final folder = CollectionFolder(
      groupId: group.id,
      parentId: nestedParentId ?? '',
      name: _str(raw['name']).trim().isEmpty ? 'Untitled Folder' : _str(raw['name']).trim(),
      variables: _kvList(raw['variable']),
    );
    folderById[id] = folder;
    rawById[id] = raw;
    folders.add(folder);
    orderOf[id] = readOrder(raw['order']);
    if (nestedParentId != null && nestedParentId.isNotEmpty) {
      parentOf[id] = nestedParentId;
    }
    for (final request in _list(raw['requests']).whereType<Map>()) {
      final requestId = _str(request['id']).trim();
      if (requestId.isNotEmpty) nestedRequestIds.add(requestId);
      _addLegacyDumpRequest(request, group, folder.id, collections);
    }
    for (final child in _list(raw['folders']).whereType<Map>()) {
      registerFolder(child, id);
    }
  }

  orderOf[''] = readOrder(collection['order']);
  for (final raw in _list(collection['folders']).whereType<Map>()) {
    registerFolder(raw, null);
  }

  for (final entry in folderById.keys.toList()) {
    final declared = _str(rawById[entry]?['folder']).trim();
    if (declared.isEmpty) continue;
    if (folderById.containsKey(declared) && declared != entry) {
      parentOf[entry] = declared;
    }
  }
  orderOf.forEach((parentId, ids) {
    if (parentId.isEmpty) return;
    for (final childId in ids) {
      if (folderById.containsKey(childId) && childId != parentId) {
        parentOf.putIfAbsent(childId, () => parentId);
      }
    }
  });

  bool createsCycle(String id, String parentId) {
    var current = parentId;
    final seen = <String>{};
    while (seen.add(current)) {
      if (current == id) return true;
      final next = parentOf[current];
      if (next == null) return false;
      current = next;
    }
    return true;
  }

  for (final entry in folderById.entries) {
    final parentId = parentOf[entry.key] ?? '';
    final parent = parentId.isNotEmpty &&
            parentId != entry.key &&
            folderById.containsKey(parentId) &&
            !createsCycle(entry.key, parentId)
        ? folderById[parentId]!
        : null;
    entry.value.parentId = parent?.id ?? '';
  }

  final orderOwner = <String, String>{};
  orderOf.forEach((parentId, ids) {
    for (final id in ids) {
      orderOwner[id] = parentId;
    }
  });

  for (final raw in _list(collection['requests']).whereType<Map>()) {
    final requestId = _str(raw['id']).trim();
    if (requestId.isNotEmpty && !nestedRequestIds.add(requestId)) continue;
    var folderId = _str(raw['folder']).trim();
    if (folderId.isEmpty) folderId = _str(raw['folderId']).trim();
    if (folderId.isEmpty) folderId = orderOwner[requestId] ?? '';
    _addLegacyDumpRequest(raw, group, folderById[folderId]?.id ?? '', collections);
  }
}

void _addLegacyDumpRequest(
  Map raw,
  CollectionGroup group,
  String folderId,
  List<CollectionEntry> collections,
) {
  final name = _str(raw['name']).trim().isEmpty ? 'Untitled Request' : _str(raw['name']).trim();
  final entry = _collection(name, {
    'method': _str(raw['method']).isEmpty ? 'GET' : _str(raw['method']).toUpperCase(),
    'url': _postmanUrl(raw['url']),
    'headers': _legacyHeaders(raw['headers']),
    'params': <dynamic>[],
    'auth': _legacyAuth(raw),
    ..._legacyBody(raw),
  })
    ..groupId = group.id
    ..folderId = folderId;
  collections.add(entry);
}

List<Map<String, dynamic>> _legacyHeaders(dynamic headers) {
  if (headers is List) {
    return headers
        .whereType<Map>()
        .where((h) => _str(h['key']).isNotEmpty && h['enabled'] != false)
        .map((h) => {'on': true, 'k': _str(h['key']), 'v': _str(h['value'])})
        .toList();
  }
  final result = <Map<String, dynamic>>[];
  for (final line in _str(headers).split('\n')) {
    final trimmed = line.trim();
    final colon = trimmed.indexOf(':');
    if (colon <= 0) continue;
    final key = trimmed.substring(0, colon).trim();
    if (key.isEmpty) continue;
    result.add({'on': true, 'k': key, 'v': trimmed.substring(colon + 1).trim()});
  }
  return result;
}

Map<String, dynamic> _legacyBody(Map raw) {
  final mode = _str(raw['dataMode']);
  if (mode == 'urlencoded' || mode == 'params' || mode == 'formdata') {
    final entries = _list(raw['data'])
        .whereType<Map>()
        .where((item) => item['enabled'] != false)
        .toList();
    if (mode == 'urlencoded') {
      return {
        'bodyMode': 'form',
        'form': entries
            .map((item) => {'on': true, 'k': _str(item['key']), 'v': _str(item['value'])})
            .toList(),
      };
    }
    return {
      'bodyMode': 'form-data',
      'formData': entries
          .map((item) => {
                'on': true,
                'k': _str(item['key']),
                'v': _str(item['value']),
                'type': 'text',
              })
          .toList(),
    };
  }
  final rawText = _str(raw['rawModeData']);
  final text = rawText.isNotEmpty ? rawText : (raw['data'] is String ? raw['data'] as String : '');
  if (text.isEmpty) return {};
  final isJson = RegExp(r'^\s*[\[{]').hasMatch(text);
  return {'bodyMode': isJson ? 'json' : 'text', 'body': text};
}

Map<String, dynamic> _legacyAuth(Map raw) {
  final helper = _str(raw['currentHelper']).toLowerCase();
  final attributes = _map(raw['helperAttributes']);
  switch (helper) {
    case 'basicauth':
      return {
        'type': 'basic',
        'username': _str(attributes['username']),
        'password': _str(attributes['password']),
      };
    case 'bearerauth':
      return {'type': 'bearer', 'token': _str(attributes['token'])};
    case 'apikeyauth':
      return {
        'type': 'apikey',
        'apiKeyName': _str(attributes['key']),
        'apiKeyValue': _str(attributes['value']),
        'apiKeyIn': _str(attributes['in']).isEmpty ? 'header' : _str(attributes['in']),
      };
    default:
      return {'type': 'none'};
  }
}

ImportResult importPostman(Map<String, dynamic> data) {
  final collections = <CollectionEntry>[];
  final variables = <KV>[];
  final seenVars = <String>{};

  void addVars(dynamic list) {
    for (final item in _list(list).whereType<Map>()) {
      final key = _str(item['key']).trim();
      if (key.isEmpty ||
          item['disabled'] == true ||
          item['enabled'] == false ||
          seenVars.contains(key)) {
        continue;
      }
      seenVars.add(key);
      variables.add(KV(k: key, v: _str(item['value'])));
    }
  }

  if (_isPostmanDump(data)) {
    final groups = <CollectionGroup>[];
    final folders = <CollectionFolder>[];
    for (final raw in _list(data['collections']).whereType<Map>()) {
      final collection = Map<String, dynamic>.from(raw);
      final infoName = _str(_map(collection['info'])['name']).trim();
      final name = infoName.isNotEmpty
          ? infoName
          : (_str(collection['name']).trim().isEmpty
              ? 'Imported Collection'
              : _str(collection['name']).trim());
      final group = CollectionGroup(name: name, variables: _kvList(collection['variable']));
      groups.add(group);
      if (collection['item'] is List) {
        _walkDumpItems(collection['item'], group, '', collections, folders);
      } else {
        _walkLegacyDumpCollection(collection, group, collections, folders);
      }
    }
    final environments = <Env>[];
    for (final environment in _list(data['environments']).whereType<Map>()) {
      final name = _str(environment['name']).trim();
      if (name.isEmpty) continue;
      environments.add(Env(name: name, vars: _kvList(environment['values'])));
    }
    return ImportResult(
      collections: collections,
      variables: const [],
      name: 'Postman Data Dump',
      environments: environments,
      globals: _kvList(data['globals']),
      groups: groups,
      folders: folders,
    );
  }

  addVars(data['variable']);
  _walkPostmanItems(data['item'], '', collections, addVars);
  final info = _map(data['info']);
  return ImportResult(
    collections: collections,
    variables: variables,
    name: _str(info['name']).isEmpty ? 'Postman Import' : _str(info['name']),
  );
}

/* ------------------------------------------------------------------ */
/* OpenAPI 3.x / Swagger 2.0                                          */
/* ------------------------------------------------------------------ */

const List<String> _methods = ['get', 'post', 'put', 'patch', 'delete', 'head', 'options'];

dynamic resolveRef(Map<String, dynamic> doc, String ref) {
  if (!ref.startsWith('#/')) return null;
  dynamic node = doc;
  for (final segment in ref.substring(2).split('/')) {
    final key = segment.replaceAll('~1', '/').replaceAll('~0', '~');
    if (node is Map && node.containsKey(key)) {
      node = node[key];
    } else {
      return null;
    }
  }
  return node;
}

Map<String, dynamic> deref(Map<String, dynamic> doc, dynamic value) {
  final map = _map(value);
  final ref = _str(map[r'$ref']);
  if (ref.isEmpty) return map;
  final resolved = resolveRef(doc, ref);
  return resolved is Map ? _map(resolved) : map;
}

Map<String, dynamic> _openApiServer(Map<String, dynamic> doc) {
  final servers = _list(doc['servers']);
  if (servers.isNotEmpty) {
    final server = _map(servers.first);
    var url = _str(server['url']);
    final variables = _map(server['variables']);
    for (final key in variables.keys) {
      url = url.replaceAll('{$key}', '{{$key}}');
    }
    return {'url': url, 'variables': variables};
  }
  if (_str(doc['host']).isNotEmpty) {
    final schemes = _list(doc['schemes']);
    final scheme = schemes.isEmpty ? 'https' : _str(schemes.first);
    return {
      'url': '$scheme://${doc['host']}${_str(doc['basePath'])}',
      'variables': <String, dynamic>{},
    };
  }
  return {'url': '{{baseUrl}}', 'variables': <String, dynamic>{}};
}

String _joinUrl(String base, String path) {
  if (base.isEmpty) return path.isEmpty ? '/' : path;
  if (path.isEmpty || path == '/') return base;
  return '${base.replaceAll(RegExp(r'/+$'), '')}/${path.replaceAll(RegExp(r'^/+'), '')}';
}

dynamic _sampleFromSchema(
  dynamic schema,
  Map<String, dynamic> doc, [
  int depth = 0,
  Set<String>? seen,
]) {
  final seenRefs = seen ?? <String>{};
  if (schema is! Map || depth > 8) return null;
  final map = _map(schema);
  final ref = _str(map[r'$ref']);
  if (ref.isNotEmpty) {
    if (seenRefs.contains(ref)) return <String, dynamic>{};
    final next = {...seenRefs, ref};
    return _sampleFromSchema(resolveRef(doc, ref), doc, depth + 1, next);
  }
  if (map.containsKey('example')) return map['example'];
  if (map.containsKey('default')) return map['default'];
  final enumValues = _list(map['enum']);
  if (enumValues.isNotEmpty) return enumValues.first;
  if (map['allOf'] is List) {
    final merged = <String, dynamic>{};
    for (final part in _list(map['allOf'])) {
      final value = _sampleFromSchema(part, doc, depth + 1, seenRefs);
      if (value is Map) merged.addAll(_map(value));
    }
    return merged;
  }
  final type = _str(map['type']).isNotEmpty
      ? _str(map['type'])
      : map['properties'] is Map
          ? 'object'
          : map['items'] != null
              ? 'array'
              : '';
  if (type == 'object') {
    final out = <String, dynamic>{};
    _map(map['properties']).forEach((key, value) {
      out[key] = _sampleFromSchema(value, doc, depth + 1, seenRefs);
    });
    return out;
  }
  if (type == 'array') {
    final sample = _sampleFromSchema(map['items'], doc, depth + 1, seenRefs);
    return [sample];
  }
  if (type == 'integer' || type == 'number') return 0;
  if (type == 'boolean') return false;
  if (type == 'string') {
    if (_str(map['format']) == 'date-time') return DateTime.now().toIso8601String();
    if (_str(map['format']) == 'date') return DateTime.now().toIso8601String().substring(0, 10);
    return '';
  }
  return null;
}

String _scalarText(dynamic value) {
  if (value == null) return '';
  if (value is Map || value is List) return jsonEncode(value);
  return '$value';
}

String _paramSample(Map<String, dynamic> param) {
  if (param.containsKey('example')) return _scalarText(param['example']);
  final schema = param['schema'] is Map ? _map(param['schema']) : param;
  if (schema.containsKey('example')) return _scalarText(schema['example']);
  final enumValues = _list(schema['enum']);
  if (enumValues.isNotEmpty) return _scalarText(enumValues.first);
  if (schema.containsKey('default')) return _scalarText(schema['default']);
  return '';
}

Map<String, dynamic> _schemaProps(dynamic schema, Map<String, dynamic> doc) {
  final resolved = deref(doc, schema);
  return _map(resolved['properties']);
}

List<Map<String, dynamic>> _formRows(dynamic schema, Map<String, dynamic> doc) {
  final props = _schemaProps(schema, doc);
  return props.entries
      .map((entry) => {
            'on': true,
            'k': entry.key,
            'v': _scalarText(_sampleFromSchema(deref(doc, entry.value), doc, 1)),
          })
      .toList();
}

List<Map<String, dynamic>> _formDataRows(dynamic schema, Map<String, dynamic> doc) {
  final props = _schemaProps(schema, doc);
  return props.entries.map((entry) {
    final prop = deref(doc, entry.value);
    final isFile =
        _str(prop['type']) == 'file' || (_str(prop['type']) == 'string' && _str(prop['format']) == 'binary');
    if (isFile) {
      return {
        'on': true,
        'k': entry.key,
        'v': '',
        'type': 'file',
        'file': {
          'name': entry.key,
          'type': 'application/octet-stream',
          'size': 0,
          'path': '',
          'stale': true,
        },
      };
    }
    return {
      'on': true,
      'k': entry.key,
      'v': _scalarText(_sampleFromSchema(prop, doc, 1)),
      'type': 'text',
    };
  }).toList();
}

String _pickMedia(List<String> types) {
  if (types.isEmpty) return '';
  for (final type in types) {
    if (type.contains('json')) return type;
  }
  for (final type in types) {
    if (type.contains('multipart/form-data')) return type;
  }
  for (final type in types) {
    if (type.contains('x-www-form-urlencoded')) return type;
  }
  return types.first;
}

Map<String, dynamic> _openApiBody(Map<String, dynamic> doc, Map<String, dynamic> operation) {
  if (doc['openapi'] != null) {
    if (operation['requestBody'] == null) return {};
    final body = deref(doc, operation['requestBody']);
    final content = _map(body['content']);
    final media = _pickMedia(content.keys.toList());
    if (media.isEmpty) return {};
    final entry = _map(content[media]);
    final schema = entry['schema'];
    if (media.contains('json')) {
      final sample = entry['example'] ?? _sampleFromSchema(schema, doc);
      return {
        'bodyMode': 'json',
        'body': const JsonEncoder.withIndent('  ').convert(sample ?? <String, dynamic>{}),
      };
    }
    if (media.contains('x-www-form-urlencoded')) {
      return {'bodyMode': 'form', 'form': _formRows(schema, doc)};
    }
    if (media.contains('multipart/form-data')) {
      return {'bodyMode': 'form-data', 'formData': _formDataRows(schema, doc)};
    }
    final sample = entry['example'] ?? _sampleFromSchema(schema, doc);
    return {'bodyMode': 'text', 'body': _scalarText(sample)};
  }

  final params = _list(operation['parameters'])
      .map((param) => deref(doc, param))
      .where((param) => param.isNotEmpty)
      .toList();
  final bodyParam = params.firstWhere((p) => _str(p['in']) == 'body', orElse: () => {});
  final formParams = params.where((p) => _str(p['in']) == 'formData').toList();
  if (bodyParam.isNotEmpty) {
    final sample = _sampleFromSchema(bodyParam['schema'], doc);
    return {
      'bodyMode': 'json',
      'body': const JsonEncoder.withIndent('  ').convert(sample ?? <String, dynamic>{}),
    };
  }
  if (formParams.isNotEmpty) {
    final hasFile = formParams.any((p) => _str(p['type']) == 'file');
    if (hasFile) {
      return {
        'bodyMode': 'form-data',
        'formData': formParams.map((param) {
          if (_str(param['type']) == 'file') {
            return {
              'on': true,
              'k': _str(param['name']),
              'v': '',
              'type': 'file',
              'file': {
                'name': _str(param['name']),
                'type': 'application/octet-stream',
                'size': 0,
                'path': '',
                'stale': true,
              },
            };
          }
          return {
            'on': true,
            'k': _str(param['name']),
            'v': _paramSample(param),
            'type': 'text',
          };
        }).toList(),
      };
    }
    return {
      'bodyMode': 'form',
      'form': formParams
          .map((param) => {'on': true, 'k': _str(param['name']), 'v': _paramSample(param)})
          .toList(),
    };
  }
  return {};
}

void _applySecurity(
  Map<String, dynamic> doc,
  dynamic security,
  Map<String, dynamic> request,
  List<Map<String, dynamic>> headers,
  List<Map<String, dynamic>> params,
  void Function(String key, String value) addVar,
) {
  final list = _list(security);
  if (list.isEmpty) return;
  final schemeName = _map(list.first).keys.isEmpty ? '' : _map(list.first).keys.first;
  final components = _map(doc['components']);
  final schemes = components['securitySchemes'] is Map
      ? _map(components['securitySchemes'])
      : _map(doc['securityDefinitions']);
  final scheme = _map(schemes[schemeName]);
  if (scheme.isEmpty) return;
  final type = _str(scheme['type']);
  if (type == 'http' && _str(scheme['scheme']).toLowerCase() == 'bearer') {
    request['auth'] = {'type': 'bearer', 'token': '{{token}}'};
    addVar('token', '');
  } else if (type == 'basic' || (type == 'http' && _str(scheme['scheme']).toLowerCase() == 'basic')) {
    request['auth'] = {
      'type': 'basic',
      'username': '{{username}}',
      'password': '{{password}}',
    };
    addVar('username', '');
    addVar('password', '');
  } else if (type == 'apiKey') {
    final key = _str(scheme['name']).isEmpty ? 'X-API-Key' : _str(scheme['name']);
    if (_str(scheme['in']) == 'query') {
      params.add({'on': true, 'k': key, 'v': '{{apiKey}}'});
    } else {
      headers.add({'on': true, 'k': key, 'v': '{{apiKey}}'});
    }
    addVar('apiKey', '');
  } else if (type == 'oauth2') {
    request['auth'] = {'type': 'bearer', 'token': '{{accessToken}}'};
    addVar('accessToken', '');
  }
}

ImportResult importOpenApi(Map<String, dynamic> doc) {
  final collections = <CollectionEntry>[];
  final variables = <KV>[];
  final seenVars = <String>{};

  void addVar(String key, String value) {
    final name = key.trim();
    if (name.isEmpty || seenVars.contains(name)) return;
    seenVars.add(name);
    variables.add(KV(k: name, v: value));
  }

  final server = _openApiServer(doc);
  _map(server['variables']).forEach((key, value) {
    addVar(key, _str(_map(value)['default']));
  });

  final paths = _map(doc['paths']);
  paths.forEach((pathKey, pathValue) {
    final pathItem = _map(pathValue);
    for (final method in _methods) {
      final operation = pathItem[method];
      if (operation is! Map) continue;
      final op = _map(operation);
      final params = <Map<String, dynamic>>[];
      final headers = <Map<String, dynamic>>[];
      final request = _emptyRequest()..['method'] = method.toUpperCase();

      final merged = [
        ..._list(pathItem['parameters']),
        ..._list(op['parameters']),
      ].map((param) => deref(doc, param)).toList();
      final seen = <String>{};
      for (final param in merged) {
        final name = _str(param['name']);
        if (name.isEmpty) continue;
        final key = '${param['in']}:$name';
        if (seen.contains(key)) continue;
        seen.add(key);
        final where = _str(param['in']);
        if (where == 'path') {
          addVar(name, _paramSample(param));
        } else if (where == 'query') {
          params.add({'on': true, 'k': name, 'v': _paramSample(param)});
        } else if (where == 'header' && !RegExp(r'^content-(type|length)$', caseSensitive: false).hasMatch(name)) {
          headers.add({'on': true, 'k': name, 'v': _paramSample(param)});
        }
      }

      final path = pathKey.replaceAllMapped(
        RegExp(r'\{([^}]+)\}'),
        (match) => '{{${match.group(1)}}}',
      );
      request['url'] = _joinUrl(_str(server['url']), path);
      request['params'] = params;
      request['headers'] = headers;
      _applySecurity(
        doc,
        op['security'] ?? doc['security'],
        request,
        headers,
        params,
        addVar,
      );
      request.addAll(_openApiBody(doc, op));

      final summary = _str(op['summary']).isNotEmpty
          ? _str(op['summary'])
          : _str(op['operationId']).isNotEmpty
              ? _str(op['operationId'])
              : '${method.toUpperCase()} $pathKey';
      final tags = _list(op['tags']);
      final tag = tags.isEmpty ? '' : '${tags.first} / ';
      collections.add(_collection('$tag$summary', request));
    }
  });

  final info = _map(doc['info']);
  return ImportResult(
    collections: collections,
    variables: variables,
    name: _str(info['title']).isEmpty ? 'OpenAPI Import' : _str(info['title']),
  );
}

/* ------------------------------------------------------------------ */
/* 导出                                                               */
/* ------------------------------------------------------------------ */

String _postmanFullUrl(ApiRequest request) {
  var url = request.url;
  final params = request.params.where((item) => item.on && item.k.trim().isNotEmpty).toList();
  if (params.isEmpty) return url;
  final query = params
      .map((item) =>
          '${Uri.encodeQueryComponent(item.k)}=${Uri.encodeQueryComponent(item.v)}')
      .join('&');
  return '$url${url.contains('?') ? '&' : '?'}$query';
}

Map<String, dynamic>? _exportPostmanBody(ApiRequest request) {
  switch (request.bodyMode) {
    case 'json':
    case 'text':
      return {
        'mode': 'raw',
        'raw': request.body,
        'options': {
          'raw': {'language': request.bodyMode == 'json' ? 'json' : 'text'},
        },
      };
    case 'form':
      return {
        'mode': 'urlencoded',
        'urlencoded': request.form
            .where((item) => item.k.trim().isNotEmpty)
            .map((item) => {
                  'key': item.k,
                  'value': item.v,
                  'type': 'text',
                  'disabled': !item.on,
                })
            .toList(),
      };
    case 'form-data':
      return {
        'mode': 'formdata',
        'formdata': request.formData.where((item) => item.k.trim().isNotEmpty).map((item) {
          return item.type == 'file'
              ? {'key': item.k, 'type': 'file', 'src': <String>[], 'disabled': !item.on}
              : {
                  'key': item.k,
                  'value': item.v,
                  'type': 'text',
                  'disabled': !item.on,
                };
        }).toList(),
      };
  }
  return null;
}

Map<String, dynamic>? _exportPostmanAuth(AuthConfig auth) {
  if (auth.type == 'bearer') {
    return {
      'type': 'bearer',
      'bearer': [
        {'key': 'token', 'value': auth.token, 'type': 'string'},
      ],
    };
  }
  if (auth.type == 'basic') {
    return {
      'type': 'basic',
      'basic': [
        {'key': 'username', 'value': auth.username, 'type': 'string'},
        {'key': 'password', 'value': auth.password, 'type': 'string'},
      ],
    };
  }
  return null;
}

Map<String, dynamic> toPostman(List<CollectionEntry> collections, Env env) {
  final items = <Map<String, dynamic>>[];
  for (final entry in collections) {
    if (entry.mode == 'ws' || entry.request == null) continue;
    final request = entry.request!;
    final item = <String, dynamic>{
      'name': entry.name,
      'request': <String, dynamic>{
        'method': request.method.toUpperCase(),
        'header': request.headers
            .where((header) => header.k.trim().isNotEmpty)
            .map((header) => {
                  'key': header.k,
                  'value': header.v,
                  'type': 'text',
                  'disabled': !header.on,
                })
            .toList(),
        'url': _postmanFullUrl(request),
      },
    };
    final body = _exportPostmanBody(request);
    if (body != null) (item['request'] as Map)['body'] = body;
    final auth = _exportPostmanAuth(request.auth);
    if (auth != null) (item['request'] as Map)['auth'] = auth;
    items.add(item);
  }

  return {
    'info': {
      'name': 'Astra Export',
      'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
    },
    'item': items,
    'variable': env.vars
        .where((item) => item.k.trim().isNotEmpty)
        .map((item) => {'key': item.k, 'value': item.v, 'type': 'string'})
        .toList(),
  };
}

Map<String, String>? _splitExportUrl(String raw, Map<String, String> varMap) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  var server = '';
  final scheme = RegExp(r'^([a-z]+://[^/]+)(.*)$', caseSensitive: false).firstMatch(text);
  if (scheme != null) {
    server = scheme.group(1)!;
    text = scheme.group(2) ?? '/';
  } else {
    final variable = RegExp(r'^(\{\{[^}]+\}\})(.*)$').firstMatch(text);
    if (variable != null) {
      server = variable.group(1)!;
      text = variable.group(2) ?? '/';
    }
  }
  if (server == '{{baseUrl}}' && RegExp(r'^https?://', caseSensitive: false).hasMatch(varMap['baseUrl'] ?? '')) {
    server = varMap['baseUrl']!;
  }
  final hashIndex = text.indexOf('#');
  if (hashIndex >= 0) text = text.substring(0, hashIndex);
  var path = text.split('?').first;
  if (path.isEmpty) path = '/';
  if (!path.startsWith('/')) path = '/$path';
  return {'server': server, 'path': path};
}

Map<String, dynamic> _schemaFromExample(dynamic value) {
  if (value == null) return {'nullable': true};
  if (value is List) {
    return {
      'type': 'array',
      'items': _schemaFromExample(value.isEmpty ? null : value.first),
    };
  }
  if (value is Map) {
    final properties = <String, dynamic>{};
    value.forEach((key, item) {
      properties['$key'] = _schemaFromExample(item);
    });
    return {'type': 'object', 'properties': properties};
  }
  if (value is num) {
    return {
      'type': value is int ? 'integer' : 'number',
      'example': value,
    };
  }
  if (value is bool) return {'type': 'boolean', 'example': value};
  return {'type': 'string', 'example': '$value'};
}

Map<String, dynamic>? _exportOpenApiBody(ApiRequest request) {
  switch (request.bodyMode) {
    case 'json':
      Map<String, dynamic> schema;
      try {
        schema = _schemaFromExample(jsonDecode(request.body.isEmpty ? '{}' : request.body));
      } catch (_) {
        schema = {'type': 'object'};
      }
      return {
        'content': {
          'application/json': {'schema': schema},
        },
      };
    case 'text':
      return {
        'content': {
          'text/plain': {'example': request.body},
        },
      };
    case 'form':
      final properties = <String, dynamic>{};
      for (final item in request.form.where((item) => item.on && item.k.trim().isNotEmpty)) {
        properties[item.k] = {'type': 'string', 'example': item.v};
      }
      return {
        'content': {
          'application/x-www-form-urlencoded': {
            'schema': {'type': 'object', 'properties': properties},
          },
        },
      };
    case 'form-data':
      final properties = <String, dynamic>{};
      for (final item in request.formData.where((item) => item.on && item.k.trim().isNotEmpty)) {
        properties[item.k] =
            item.type == 'file' ? {'type': 'string', 'format': 'binary'} : {'type': 'string', 'example': item.v};
      }
      return {
        'content': {
          'multipart/form-data': {
            'schema': {'type': 'object', 'properties': properties},
          },
        },
      };
  }
  return null;
}

Map<String, dynamic> toOpenApi(List<CollectionEntry> collections, Env env) {
  final doc = <String, dynamic>{
    'openapi': '3.0.3',
    'info': {'title': 'Astra Export API', 'version': '1.0.0'},
    'servers': [
      {'url': 'http://localhost'},
    ],
    'paths': <String, dynamic>{},
  };
  final varMap = <String, String>{};
  for (final item in env.vars) {
    if (item.k.trim().isNotEmpty) varMap[item.k] = item.v;
  }
  final servers = <String>[];
  final schemes = <String, dynamic>{};

  for (final entry in collections) {
    if (entry.mode == 'ws' || entry.request == null) continue;
    final request = entry.request!;
    final split = _splitExportUrl(request.url, varMap);
    if (split == null) continue;
    final server = split['server']!;
    if (server.isNotEmpty && !server.contains('{{')) servers.add(server);
    final path = split['path']!.replaceAllMapped(
      RegExp(r'\{\{([^}]+)\}\}'),
      (match) => '{${match.group(1)}}',
    );
    final method = request.method.toLowerCase();
    final paths = doc['paths'] as Map<String, dynamic>;
    final pathItem = paths[path] is Map ? _map(paths[path]) : <String, dynamic>{};
    if (pathItem.containsKey(method)) continue;

    final pathParams = <String>[];
    for (final match in RegExp(r'\{([^}]+)\}').allMatches(path)) {
      final name = match.group(1)!;
      if (!pathParams.contains(name)) pathParams.add(name);
    }
    final queryParams = request.params
        .where((item) => item.on && item.k.trim().isNotEmpty)
        .map((item) => {
              'name': item.k,
              'in': 'query',
              'required': false,
              'schema': {'type': 'string'},
              'example': item.v,
            })
        .toList();

    final operation = <String, dynamic>{
      'summary': entry.name,
      'operationId': '${method}_$path'
          .replaceAll(RegExp(r'[{}]'), '')
          .replaceAll(RegExp(r'[^\w]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), ''),
      'parameters': [
        ...pathParams.map((name) => {
              'name': name,
              'in': 'path',
              'required': true,
              'schema': {'type': 'string'},
            }),
        ...queryParams,
      ],
      'responses': {
        '200': {'description': 'OK'},
      },
    };
    final body = _exportOpenApiBody(request);
    if (body != null) operation['requestBody'] = body;
    if (request.auth.type == 'bearer') {
      operation['security'] = [
        {
          'bearerAuth': <dynamic>[],
        },
      ];
      schemes['bearerAuth'] = {'type': 'http', 'scheme': 'bearer'};
    } else if (request.auth.type == 'basic') {
      operation['security'] = [
        {
          'basicAuth': <dynamic>[],
        },
      ];
      schemes['basicAuth'] = {'type': 'http', 'scheme': 'basic'};
    }
    pathItem[method] = operation;
    paths[path] = pathItem;
  }

  if (servers.isNotEmpty) {
    doc['servers'] = servers.toSet().map((url) => {'url': url}).toList();
  }
  if (schemes.isNotEmpty) {
    doc['components'] = {'securitySchemes': schemes};
  }
  return doc;
}

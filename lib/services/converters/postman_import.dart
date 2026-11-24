part of '../converters.dart';

/* ------------------------------------------------------------------ */
/* Postman v2.0 / v2.1                                                */
/* ------------------------------------------------------------------ */

/// Splits "?a=1&b=2" off a URL so the query is shown in the Params table.
({String base, List<Map<String, dynamic>> params}) _splitQuery(String url) {
  final index = url.indexOf('?');
  if (index < 0) return (base: url, params: <Map<String, dynamic>>[]);
  final fragment = url.indexOf('#', index);
  final query = url.substring(index + 1, fragment < 0 ? url.length : fragment);
  final params = <Map<String, dynamic>>[];
  for (final pair in query.split('&').where((part) => part.isNotEmpty)) {
    final separator = pair.indexOf('=');
    params.add({
      'on': true,
      'k': _decodeQuery(separator < 0 ? pair : pair.substring(0, separator)),
      'v': _decodeQuery(separator < 0 ? '' : pair.substring(separator + 1)),
    });
  }
  return (base: url.substring(0, index), params: params);
}

String _decodeQuery(String text) {
  try {
    return Uri.decodeQueryComponent(text);
  } catch (_) {
    return text;
  }
}

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
  final split = _splitQuery(_postmanUrl(source['url']));
  final params = <Map<String, dynamic>>[];
  final auth = _postmanAuth(_map(source['auth']), headers, params);
  for (final param in split.params) {
    if (!params.any((e) => e['k'] == param['k'] && e['v'] == param['v'])) {
      params.add(param);
    }
  }

  return _collection(name, {
    'method': _str(source['method']).isEmpty ? 'GET' : _str(source['method']).toUpperCase(),
    'url': split.base,
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
    addVars(_variablesFrom(raw));
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
        variables: _variablesFrom(raw),
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
      variables: _variablesFrom(raw),
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
  final split = _splitQuery(_postmanUrl(raw['url']));
  final params = <Map<String, dynamic>>[];
  for (final entry in [..._list(raw['params']), ..._list(raw['query'])]) {
    if (entry is! Map) continue;
    final key = _str(entry['key']).trim().isEmpty
        ? _str(entry['name']).trim()
        : _str(entry['key']).trim();
    if (key.isEmpty) continue;
    params.add({
      'on': entry['disabled'] != true && entry['enabled'] != false,
      'k': key,
      'v': _str(entry['value']),
    });
  }
  for (final param in split.params) {
    if (!params.any((e) => e['k'] == param['k'] && e['v'] == param['v'])) {
      params.add(param);
    }
  }
  final entry = _collection(name, {
    'method': _str(raw['method']).isEmpty ? 'GET' : _str(raw['method']).toUpperCase(),
    'url': split.base,
    'headers': _legacyHeaders(raw['headers']),
    'params': params,
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

  void addVars(dynamic source) {
    final entries = source is Iterable<KV>
        ? source.map((kv) => {'key': kv.k, 'value': kv.v, 'disabled': !kv.on})
        : _list(source).whereType<Map>();
    for (final item in entries) {
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
      final group = CollectionGroup(name: name, variables: _variablesFrom(collection));
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
      globals: _globalsFrom(data['globals']),
      groups: groups,
      folders: folders,
    );
  }

  addVars(_variablesFrom(data));
  _walkPostmanItems(data['item'], '', collections, addVars);
  final info = _map(data['info']);
  return ImportResult(
    collections: collections,
    variables: variables,
    name: _str(info['name']).isEmpty ? 'Postman Import' : _str(info['name']),
  );
}

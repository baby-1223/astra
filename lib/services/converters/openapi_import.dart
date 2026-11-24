part of '../converters.dart';

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

part of '../converters.dart';

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

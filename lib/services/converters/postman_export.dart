part of '../converters.dart';

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

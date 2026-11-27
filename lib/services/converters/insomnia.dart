part of '../converters.dart';

final _insomniaVariable = RegExp(r'\{\{\s*_\s*\.\s*([A-Za-z0-9_\-]+)\s*\}\}');
final _astraVariable = RegExp(r'\{\{\s*([A-Za-z0-9_\-]+)\s*\}\}');

String _toInsomniaVariables(String text) =>
    text.replaceAllMapped(_astraVariable, (m) => '{{ _.${m.group(1)} }}');

String _fromInsomniaVariables(String text) =>
    text.replaceAllMapped(_insomniaVariable, (m) => '{{${m.group(1)}}}');

/// Imports an Insomnia v4 export. Workspaces become collections, request groups
/// become nested folders and environment resources become Astra environments.
ImportResult importInsomnia(Map<String, dynamic> data) {
  final resources = <Map<String, dynamic>>[];
  final raw = data['resources'];
  if (raw is List) {
    for (final item in raw) {
      if (item is Map) resources.add(Map<String, dynamic>.from(item));
    }
  } else if (data['_type'] != null) {
    resources.add(data);
  }
  if (resources.isEmpty) {
    throw const FormatException('No Insomnia resources found in this file');
  }

  final workspaces = resources.where((r) => r['_type'] == 'workspace').toList();
  final requestGroups =
      resources.where((r) => r['_type'] == 'request_group').toList();
  final requests = resources.where((r) => r['_type'] == 'request').toList();
  final envResources =
      resources.where((r) => r['_type'] == 'environment').toList();

  final collections = <CollectionEntry>[];
  final groups = <CollectionGroup>[];
  final folders = <CollectionFolder>[];
  final attached = <String>{};

  void walkRequests(
    String groupId,
    String parentId,
    String folderId,
  ) {
    for (final group in requestGroups.where((r) => r['parentId'] == parentId)) {
      final folder = CollectionFolder(
        groupId: groupId,
        parentId: folderId,
        name: _str(group['name']).trim().isEmpty
            ? 'Folder'
            : _str(group['name']).trim(),
        description: _str(group['description']),
      );
      folders.add(folder);
      walkRequests(groupId, _str(group['_id']), folder.id);
    }
    for (final request in requests.where((r) => r['parentId'] == parentId)) {
      attached.add(_str(request['_id']));
      collections.add(CollectionEntry(
        groupId: groupId,
        folderId: folderId,
        name: _str(request['name']).trim().isEmpty
            ? 'Untitled'
            : _str(request['name']).trim(),
        request: _parseInsomniaRequest(request),
      ));
    }
  }

  List<Map<String, dynamic>> workspaceList = workspaces;
  if (workspaceList.isEmpty) {
    workspaceList = [
      {'_id': '', 'name': 'Imported Insomnia'},
    ];
  }

  for (final workspace in workspaceList) {
    final group = CollectionGroup(
      name: _str(workspace['name']).trim().isEmpty
          ? 'Imported Insomnia'
          : _str(workspace['name']).trim(),
      description: _str(workspace['description']),
    );
    groups.add(group);
    walkRequests(group.id, _str(workspace['_id']), '');
  }

  // Requests whose parent group is missing still need a home.
  if (collections.length < requests.length) {
    final home = groups.first;
    for (final request in requests) {
      if (attached.contains(_str(request['_id']))) continue;
      collections.add(CollectionEntry(
        groupId: home.id,
        name: _str(request['name']).trim().isEmpty
            ? 'Untitled'
            : _str(request['name']).trim(),
        request: _parseInsomniaRequest(request),
      ));
    }
  }

  final environments = <Env>[];
  for (final resource in envResources) {
    final vars = <KV>[];
    final dataMap = resource['data'];
    if (dataMap is Map) {
      dataMap.forEach((key, value) {
        vars.add(KV(
          k: '$key',
          v: _fromInsomniaVariables(value is Map ? _str(value) : '$value'),
        ));
      });
    }
    environments.add(Env(
      name: _str(resource['name']).trim().isEmpty
          ? 'Imported Insomnia'
          : _str(resource['name']).trim(),
      vars: vars.isEmpty ? [KV()] : vars,
    ));
  }

  return ImportResult(
    collections: collections,
    variables: const [],
    name: groups.first.name,
    environments: environments,
    groups: groups,
    folders: folders,
  );
}

ApiRequest _parseInsomniaRequest(Map<String, dynamic> raw) {
  final request = ApiRequest(
    method: _str(raw['method']).trim().isEmpty
        ? 'GET'
        : _str(raw['method']).trim().toUpperCase(),
    url: _fromInsomniaVariables(_str(raw['url'])),
    params: _insomniaParams(raw['parameters']),
    headers: _insomniaParams(raw['headers']),
  );
  final body = raw['body'];
  if (body is Map) _applyInsomniaBody(request, Map<String, dynamic>.from(body));
  final auth = raw['authentication'];
  if (auth is Map) _applyInsomniaAuth(request, Map<String, dynamic>.from(auth));
  return request;
}

List<KV> _insomniaParams(dynamic raw) {
  final list = <KV>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is! Map) continue;
      final name = _str(item['name']).trim();
      if (name.isEmpty) continue;
      list.add(KV(
        on: item['disabled'] != true,
        k: name,
        v: _fromInsomniaVariables(_str(item['value'])),
      ));
    }
  }
  return list.isEmpty ? [KV()] : list;
}

void _applyInsomniaBody(ApiRequest request, Map<String, dynamic> body) {
  final mime = _str(body['mimeType']).toLowerCase();
  final params = body['params'];
  if (mime.contains('multipart/form-data')) {
    request.bodyMode = 'form-data';
    request.formData = _insomniaFormRows(params, files: true);
    return;
  }
  if (mime.contains('x-www-form-urlencoded')) {
    request.bodyMode = 'form';
    request.form = _insomniaParams(params);
    return;
  }
  final text = _fromInsomniaVariables(_str(body['text']));
  request.body = text;
  final trimmed = text.trimLeft();
  request.bodyMode =
      mime.contains('json') || trimmed.startsWith('{') || trimmed.startsWith('[')
          ? 'json'
          : (text.isEmpty ? 'none' : 'text');
}

List<FormRow> _insomniaFormRows(dynamic raw, {required bool files}) {
  final rows = <FormRow>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is! Map) continue;
      final name = _str(item['name']).trim();
      if (name.isEmpty) continue;
      rows.add(FormRow(
        on: item['disabled'] != true,
        k: name,
        v: _fromInsomniaVariables(_str(item['value'])),
        type: files && item['type'] == 'file' ? 'file' : 'text',
      ));
    }
  }
  return rows.isEmpty ? [FormRow()] : rows;
}

void _applyInsomniaAuth(ApiRequest request, Map<String, dynamic> auth) {
  switch (_str(auth['type']).toLowerCase()) {
    case 'bearer':
      request.auth = AuthConfig(
        type: 'bearer',
        token: _fromInsomniaVariables(_str(auth['token'])),
      );
    case 'basic':
      request.auth = AuthConfig(
        type: 'basic',
        username: _fromInsomniaVariables(_str(auth['username'])),
        password: _fromInsomniaVariables(_str(auth['password'])),
      );
    case 'apikey':
      request.auth = AuthConfig(
        type: 'apikey',
        apiKeyName: _fromInsomniaVariables(_str(auth['key'])),
        apiKeyValue: _fromInsomniaVariables(_str(auth['value'])),
        apiKeyIn: _str(auth['addTo']) == 'query' ? 'query' : 'header',
      );
  }
}

/// Exports the whole workspace as an Insomnia v4 file.
Map<String, dynamic> toInsomnia({
  required List<CollectionGroup> groups,
  required List<CollectionFolder> folders,
  required List<CollectionEntry> collections,
  required List<Env> environments,
}) {
  const workspaceId = 'wrk_astra';
  final resources = <Map<String, dynamic>>[
    {
      '_id': workspaceId,
      '_type': 'workspace',
      'name': 'Astra',
      'description': '',
      'scope': 'collection',
    },
  ];

  String addFolder(CollectionFolder folder, String parentResourceId) {
    final id = 'fld_${folder.id}';
    resources.add({
      '_id': id,
      '_type': 'request_group',
      'parentId': parentResourceId,
      'name': folder.name,
      'description': folder.description,
    });
    return id;
  }

  for (final group in groups) {
    final groupId = 'fld_${group.id}';
    resources.add({
      '_id': groupId,
      '_type': 'request_group',
      'parentId': workspaceId,
      'name': group.name,
      'description': group.description,
    });

    void walk(String parentFolderId, String parentResourceId) {
      for (final folder
          in folders.where((f) => f.groupId == group.id && f.parentId == parentFolderId)) {
        final resourceId = addFolder(folder, parentResourceId);
        walk(folder.id, resourceId);
      }
      for (final entry in collections.where((c) =>
          c.groupId == group.id &&
          c.mode == 'http' &&
          c.folderId == parentFolderId)) {
        resources.add(_insomniaRequest(entry, parentResourceId));
      }
    }

    walk('', groupId);
  }

  for (final env in environments) {
    resources.add({
      '_id': 'env_${env.id}',
      '_type': 'environment',
      'parentId': workspaceId,
      'name': env.name,
      'data': {
        for (final kv in env.vars)
          if (kv.k.trim().isNotEmpty) kv.k: _toInsomniaVariables(kv.v),
      },
    });
  }

  return {
    '_type': 'export',
    '__export_format': 4,
    '__export_source': 'astra',
    'resources': resources,
  };
}


Map<String, dynamic> _insomniaRequest(
  CollectionEntry entry,
  String parentId,
) {
  final request = entry.request ?? ApiRequest();
  final resource = <String, dynamic>{
    '_id': 'req_${entry.id}',
    '_type': 'request',
    'parentId': parentId,
    'name': entry.name,
    'description': entry.description,
    'method': request.method.toUpperCase(),
    'url': _toInsomniaVariables(request.url),
    'parameters': [
      for (final kv in request.params)
        if (kv.k.trim().isNotEmpty) _insomniaParam(kv),
    ],
    'headers': [
      for (final kv in request.headers)
        if (kv.k.trim().isNotEmpty) _insomniaParam(kv),
    ],
  };
  final body = _insomniaBody(request);
  if (body != null) resource['body'] = body;
  final auth = _insomniaAuth(request.auth);
  if (auth != null) resource['authentication'] = auth;
  return resource;
}

Map<String, dynamic> _insomniaParam(KV kv) => {
      'name': kv.k,
      'value': _toInsomniaVariables(kv.v),
      if (!kv.on) 'disabled': true,
    };

Map<String, dynamic>? _insomniaBody(ApiRequest request) {
  switch (request.bodyMode) {
    case 'json':
      return {
        'mimeType': 'application/json',
        'text': _toInsomniaVariables(request.body),
      };
    case 'text':
      return {
        'mimeType': 'text/plain',
        'text': _toInsomniaVariables(request.body),
      };
    case 'form':
      return {
        'mimeType': 'application/x-www-form-urlencoded',
        'params': [
          for (final kv in request.form)
            if (kv.k.trim().isNotEmpty)
              {
                'name': kv.k,
                'value': _toInsomniaVariables(kv.v),
                if (!kv.on) 'disabled': true,
              },
        ],
      };
    case 'form-data':
      return {
        'mimeType': 'multipart/form-data',
        'params': [
          for (final row in request.formData)
            if (row.k.trim().isNotEmpty)
              {
                'name': row.k,
                'value': _toInsomniaVariables(row.v),
                'type': row.type == 'file' ? 'file' : 'text',
                if (!row.on) 'disabled': true,
              },
        ],
      };
    default:
      return null;
  }
}

Map<String, dynamic>? _insomniaAuth(AuthConfig auth) {
  switch (auth.type.toLowerCase()) {
    case 'bearer':
      return {
        'type': 'bearer',
        'token': _toInsomniaVariables(auth.token),
      };
    case 'basic':
      return {
        'type': 'basic',
        'username': _toInsomniaVariables(auth.username),
        'password': _toInsomniaVariables(auth.password),
      };
    case 'apikey':
      return {
        'type': 'apikey',
        'key': _toInsomniaVariables(auth.apiKeyName),
        'value': _toInsomniaVariables(auth.apiKeyValue),
        'addTo': auth.apiKeyIn == 'query' ? 'query' : 'header',
      };
    default:
      return null;
  }
}

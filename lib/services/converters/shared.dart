part of '../converters.dart';

/// Parses key/value entries from arrays or legacy key/value maps.
/// Disabled entries are kept with [KV.on] set to false.
List<KV> _kvList(dynamic list) {
  if (list is Map) {
    final result = <KV>[];
    list.forEach((key, raw) {
      final name = _str(key).trim();
      if (name.isEmpty) return;
      if (raw is Map) {
        result.add(KV(
          on: raw['disabled'] != true && raw['enabled'] != false,
          k: name,
          v: _str(raw['value']),
        ));
      } else {
        result.add(KV(k: name, v: _str(raw)));
      }
    });
    return result;
  }
  return _list(list)
      .whereType<Map>()
      .where((item) => _str(item['key']).trim().isNotEmpty)
      .map((item) => KV(
            on: item['disabled'] != true && item['enabled'] != false,
            k: _str(item['key']).trim(),
            v: _str(item['value']),
          ))
      .toList();
}

/// Reads collection/folder variables from "variable", "variables" array or map.
List<KV> _variablesFrom(Map raw) {
  final variable = raw['variable'];
  if (variable != null) return _kvList(variable);
  final variables = raw['variables'];
  if (variables != null) return _kvList(variables);
  return const [];
}

/// Reads globals from a dump: plain key/value entries or globals objects with "values".
List<KV> _globalsFrom(dynamic value) {
  final result = <KV>[];
  if (value is List) {
    for (final entry in value) {
      if (entry is! Map) continue;
      if (entry['values'] is List) {
        result.addAll(_kvList(entry['values']));
      } else {
        result.addAll(_kvList([entry]));
      }
    }
  } else if (value is Map) {
    result.addAll(_kvList(value));
  }
  final seen = <String>{};
  return result
      .where((kv) => kv.on && kv.k.isNotEmpty && seen.add(kv.k))
      .toList();
}

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

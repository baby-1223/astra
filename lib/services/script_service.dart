import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';

import '../models.dart';

class ScriptLogEntry {
  final String level; // log | warn | error
  final String message;

  const ScriptLogEntry(this.level, this.message);
}

class ScriptTestResult {
  final String name;
  final bool passed;
  final String? error;

  const ScriptTestResult(this.name, {required this.passed, this.error});
}

class ScriptInput {
  final String method;
  final String url;
  final String bodyMode;
  final String body;
  final Map<String, String> headers;
  final Map<String, String> env;
  final Map<String, String> vars;
  final Map<String, String> globals;
  final Map<String, String> collection;
  final String requestName;
  final String event; // prerequest | test

  const ScriptInput({
    required this.method,
    required this.url,
    required this.bodyMode,
    required this.body,
    required this.headers,
    required this.env,
    required this.vars,
    this.globals = const {},
    this.collection = const {},
    required this.requestName,
    required this.event,
  });
}

class ScriptOutcome {
  final String method;
  final String url;
  final String bodyMode;
  final String body;
  final List<ScriptHeader> headers;
  final Map<String, String> env;
  final Map<String, String> vars;
  final Map<String, String> globals;
  final String? nextRequest;
  final List<ScriptLogEntry> logs;
  final List<ScriptTestResult> tests;
  final String? error;

  const ScriptOutcome({
    required this.method,
    required this.url,
    required this.bodyMode,
    required this.body,
    required this.headers,
    required this.env,
    required this.vars,
    this.globals = const {},
    this.nextRequest,
    required this.logs,
    required this.tests,
    this.error,
  });
}

class ScriptHeader {
  final String key;
  final String value;
  final bool disabled;

  const ScriptHeader(this.key, this.value, {this.disabled = false});
}

/// 基于 flutter_js（macOS 使用系统 JavaScriptCore，Windows 使用内置 QuickJS）
/// 执行 Postman 风格的前置 / 后置脚本，并把脚本对请求、环境变量的修改回传给调用方。
class ScriptService {
  ScriptOutcome? run({
    required String source,
    required ScriptInput input,
    HttpResult? response,
  }) {
    if (source.trim().isEmpty) return null;
    JavascriptRuntime? runtime;
    try {
      runtime = getJavascriptRuntime(xhr: false);
      runtime.evaluate(_prelude);
      runtime.evaluate(_seed(input, response));

      final wrapped =
          'try {\n$source\n} catch (e) { __astraError = (e && e.message) ? e.message : String(e); }';
      final result = runtime.evaluate(wrapped);

      final dumpResult = runtime.evaluate('__astraDump()');
      final dumpText = dumpResult.stringResult;
      if (dumpText.isEmpty || dumpText == 'undefined' || dumpText == 'null') {
        return _failure(result.stringResult);
      }
      final dynamic decoded = jsonDecode(dumpText);
      if (decoded is! Map) return _failure('Failed to parse script state');

      return _parse(
        Map<String, dynamic>.from(decoded),
        runError: result.isError ? result.stringResult : null,
      );
    } catch (err) {
      return _failure('$err');
    } finally {
      try {
        runtime?.dispose();
      } catch (_) {}
    }
  }

  ScriptOutcome _failure(String message) => ScriptOutcome(
        method: 'GET',
        url: '',
        bodyMode: 'none',
        body: '',
        headers: const [],
        env: const {},
        vars: const {},
        logs: const [],
        tests: const [],
        error: message,
      );

  ScriptOutcome _parse(Map<String, dynamic> data, {String? runError}) {
    final request = data['request'] is Map
        ? Map<String, dynamic>.from(data['request'] as Map)
        : <String, dynamic>{};
    final headers = <ScriptHeader>[];
    final rawHeaders = request['headers'];
    if (rawHeaders is List) {
      for (final raw in rawHeaders.whereType<Map>()) {
        final key = '${raw['key'] ?? ''}'.trim();
        if (key.isEmpty) continue;
        headers.add(ScriptHeader(
          key,
          '${raw['value'] ?? ''}',
          disabled: raw['disabled'] == true,
        ));
      }
    }

    final logs = <ScriptLogEntry>[];
    final rawLogs = data['logs'];
    if (rawLogs is List) {
      for (final raw in rawLogs.whereType<Map>()) {
        logs.add(ScriptLogEntry('${raw['level'] ?? 'log'}', '${raw['message'] ?? ''}'));
      }
    }

    final tests = <ScriptTestResult>[];
    final rawTests = data['tests'];
    if (rawTests is List) {
      for (final raw in rawTests.whereType<Map>()) {
        tests.add(ScriptTestResult(
          '${raw['name'] ?? 'Unnamed assertion'}',
          passed: raw['passed'] == true,
          error: raw['error'] == null ? null : '${raw['error']}',
        ));
      }
    }

    final error = data['error'] == null || '${data['error']}'.isEmpty
        ? runError
        : '${data['error']}';

    return ScriptOutcome(
      method: '${request['method'] ?? 'GET'}'.toUpperCase(),
      url: '${request['url'] ?? ''}',
      bodyMode: '${request['bodyMode'] ?? 'none'}',
      body: '${request['body'] ?? ''}',
      headers: headers,
      env: _stringMap(data['env']),
      vars: _stringMap(data['vars']),
      globals: _stringMap(data['globals']),
      nextRequest: data['next'] == null || '${data['next']}'.isEmpty
          ? null
          : '${data['next']}',
      logs: logs,
      tests: tests,
      error: error,
    );
  }

  Map<String, String> _stringMap(dynamic raw) {
    final result = <String, String>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final name = '$key'.trim();
        if (name.isNotEmpty) result[name] = value == null ? '' : '$value';
      });
    }
    return result;
  }

  String _seed(ScriptInput input, HttpResult? response) {
    final buffer = StringBuffer();
    buffer.writeln('__astraEnv = ${_jsJson(input.env)};');
    buffer.writeln('__astraVars = ${_jsJson(input.vars)};');
    buffer.writeln('__astraGlobals = ${_jsJson(input.globals)};');
    buffer.writeln('__astraCollection = ${_jsJson(input.collection)};');
    buffer.writeln('__astraNext = null;');
    buffer.writeln('__astraSkip = false;');
    buffer.writeln('__astraInfo = ${_jsJson({
          'eventName': input.event,
          'requestName': input.requestName,
        })};');
    buffer.writeln('pm.info = __astraInfo;');
    buffer.writeln('__astraRequest = ${_jsJson({
          'method': input.method,
          'url': input.url,
          'bodyMode': input.bodyMode,
          'body': input.body,
          'headers': input.headers.entries
              .map((entry) => {'key': entry.key, 'value': entry.value, 'disabled': false})
              .toList(),
        })};');
    if (response != null) {
      final headerList = <Map<String, String>>[];
      final headerMap = <String, String>{};
      response.headers.forEach((key, values) {
        final joined = values.join(', ');
        headerList.add({'key': key, 'value': joined});
        headerMap[key.toLowerCase()] = joined;
      });
      final text = response.text ?? '';
      buffer.writeln('__astraBuildResponse(${_jsJson({
            'code': response.status,
            'reason': response.reason,
            'status': response.reason,
            'ms': response.ms,
            'size': response.size,
            'text': text.length > 2000000 ? text.substring(0, 2000000) : text,
            'headerMap': headerMap,
            'headerList': headerList,
          })});');
    }
    return buffer.toString();
  }

  String _jsJson(Object value) {
    final encoded = jsonEncode(value);
    return encoded.replaceAll('\u2028', '\\u2028').replaceAll('\u2029', '\\u2029');
  }

  static const String _prelude = r'''
var __astraEnv = {};
var __astraVars = {};
var __astraLogs = [];
var __astraTests = [];
var __astraError = null;
var __astraRequest = { method: 'GET', url: '', headers: [], bodyMode: 'none', body: '' };
var __astraResponse = null;
var __astraInfo = { eventName: 'prerequest', requestName: '' };

function __astraFmt(value) {
  try {
    if (typeof value === 'string') return value;
    if (value === undefined) return 'undefined';
    if (value === null) return 'null';
    if (value instanceof Error) return value.message;
    var text = JSON.stringify(value);
    return text === undefined ? String(value) : text;
  } catch (e) {
    return String(value);
  }
}

function __astraPush(level, args) {
  var parts = [];
  for (var i = 0; i < args.length; i++) parts.push(__astraFmt(args[i]));
  __astraLogs.push({ level: level, message: parts.join(' ') });
}

var console = {
  log: function () { __astraPush('log', arguments); },
  info: function () { __astraPush('log', arguments); },
  debug: function () { __astraPush('log', arguments); },
  warn: function () { __astraPush('warn', arguments); },
  error: function () { __astraPush('error', arguments); }
};

function __astraReplaceIn(input) {
  return String(input).replace(/\{\{\s*([\w.-]+)\s*\}\}/g, function (match, key) {
    if (Object.prototype.hasOwnProperty.call(__astraVars, key)) return __astraVars[key];
    if (Object.prototype.hasOwnProperty.call(__astraEnv, key)) return __astraEnv[key];
    return match;
  });
}

function __astraVarStore(resolveStore) {
  return {
    get: function (key) { return resolveStore()[String(key)]; },
    has: function (key) {
      return Object.prototype.hasOwnProperty.call(resolveStore(), String(key));
    },
    set: function (key, value) {
      resolveStore()[String(key)] = value == null ? '' : String(value);
    },
    unset: function (key) { delete resolveStore()[String(key)]; },
    clear: function () {
      var store = resolveStore();
      for (var key in store) {
        if (Object.prototype.hasOwnProperty.call(store, key)) delete store[key];
      }
    },
    replaceIn: function (input) { return __astraReplaceIn(input); },
    toObject: function () {
      var store = resolveStore();
      var out = {};
      for (var key in store) {
        if (Object.prototype.hasOwnProperty.call(store, key)) out[key] = store[key];
      }
      return out;
    }
  };
}

var __astraHeaders = {
  add: function (item) {
    if (!item) return;
    var key = item.key !== undefined ? item.key : item.name;
    if (key === undefined || key === null || String(key).trim() === '') return;
    __astraRequest.headers.push({
      key: String(key).trim(),
      value: item.value == null ? '' : String(item.value),
      disabled: item.disabled === true
    });
  },
  upsert: function (item) {
    if (!item) return;
    var key = item.key !== undefined ? item.key : item.name;
    if (key === undefined || key === null) return;
    var target = String(key).trim().toLowerCase();
    for (var i = 0; i < __astraRequest.headers.length; i++) {
      if (String(__astraRequest.headers[i].key).toLowerCase() === target) {
        __astraRequest.headers[i].value = item.value == null ? '' : String(item.value);
        __astraRequest.headers[i].disabled = item.disabled === true;
        return;
      }
    }
    __astraHeaders.add(item);
  },
  remove: function (key) {
    var target = String(key).toLowerCase();
    __astraRequest.headers = __astraRequest.headers.filter(function (header) {
      return String(header.key).toLowerCase() !== target;
    });
  },
  get: function (key) {
    var target = String(key).toLowerCase();
    for (var i = 0; i < __astraRequest.headers.length; i++) {
      if (String(__astraRequest.headers[i].key).toLowerCase() === target) {
        return __astraRequest.headers[i].value;
      }
    }
    return undefined;
  },
  has: function (key) { return __astraHeaders.get(key) !== undefined; },
  each: function (fn) { __astraRequest.headers.forEach(fn); },
  toObject: function () {
    var out = {};
    __astraRequest.headers.forEach(function (header) {
      if (!header.disabled) out[header.key] = header.value;
    });
    return out;
  }
};

function __astraExpect(actual, negate) {
  var api = {};
  function assert(condition, message) {
    if (negate) {
      if (condition) throw new Error(message || 'Assertion failed');
    } else if (!condition) {
      throw new Error(message || 'Assertion failed');
    }
  }
  function show(value) {
    try { return JSON.stringify(value); } catch (e) { return String(value); }
  }
  function equal(expected) {
    assert(actual === expected, 'Expected ' + show(expected) + ', got ' + show(actual));
    return api;
  }
  function eql(expected) {
    assert(show(actual) === show(expected), 'Expected ' + show(expected) + ', got ' + show(actual));
    return api;
  }
  function above(value) {
    assert(actual > value, 'Expected a value greater than ' + value + ', got ' + show(actual));
    return api;
  }
  function least(value) {
    assert(actual >= value, 'Expected a value at least ' + value + ', got ' + show(actual));
    return api;
  }
  function below(value) {
    assert(actual < value, 'Expected a value less than ' + value + ', got ' + show(actual));
    return api;
  }
  function most(value) {
    assert(actual <= value, 'Expected a value at most ' + value + ', got ' + show(actual));
    return api;
  }
  function within(low, high) {
    assert(actual >= low && actual <= high, 'Expected a value between ' + low + ' and ' + high + ', got ' + show(actual));
    return api;
  }
  function match(pattern) {
    assert(new RegExp(pattern).test(String(actual)), 'Expected to match ' + pattern + ', got ' + show(actual));
    return api;
  }
  function include(value) {
    var ok = false;
    if (typeof actual === 'string') {
      ok = actual.indexOf(String(value)) >= 0;
    } else if (actual && typeof actual.length === 'number') {
      for (var i = 0; i < actual.length; i++) {
        if (actual[i] === value) { ok = true; break; }
      }
    } else if (actual && typeof actual === 'object') {
      for (var key in actual) {
        if (actual[key] === value) { ok = true; break; }
      }
    }
    assert(ok, 'Expected to include ' + show(value));
    return api;
  }
  function property(name, value) {
    var source = Object(actual);
    var exists = actual !== null && actual !== undefined &&
      Object.prototype.hasOwnProperty.call(source, name);
    if (arguments.length > 1) {
      assert(exists && show(actual[name]) === show(value), 'Expected property ' + name + ' to be ' + show(value));
    } else {
      assert(exists, 'Expected to have property ' + name);
    }
    return api;
  }
  function lengthOf(value) {
    assert(actual !== null && actual !== undefined && actual.length === value, 'Expected length ' + value);
    return api;
  }
  function typeOf(type) {
    var target = String(type).toLowerCase();
    var ok;
    if (target === 'array') ok = Array.isArray(actual);
    else if (target === 'null') ok = actual === null;
    else if (target === 'object') ok = actual !== null && typeof actual === 'object' && !Array.isArray(actual);
    else ok = typeof actual === target;
    var real = Array.isArray(actual) ? 'array' : (actual === null ? 'null' : typeof actual);
    assert(ok, 'Expected type ' + type + ', got ' + real);
    return api;
  }
  function constProp(name, check, message) {
    Object.defineProperty(api, name, {
      get: function () {
        assert(check(), message);
        return api;
      }
    });
  }

  api.equal = equal;
  api.equals = equal;
  api.eq = equal;
  api.eql = eql;
  api.eqls = eql;
  api.above = above;
  api.greaterThan = above;
  api.gt = above;
  api.least = least;
  api.gte = least;
  api.below = below;
  api.lessThan = below;
  api.lt = below;
  api.most = most;
  api.lte = most;
  api.within = within;
  api.match = match;
  api.matches = match;
  api.include = include;
  api.includes = include;
  api.contain = include;
  api.contains = include;
  api.property = property;
  api.lengthOf = lengthOf;
  api.a = typeOf;
  api.an = typeOf;

  ['to', 'be', 'been', 'is', 'that', 'which', 'and', 'has', 'have', 'with', 'at', 'of',
   'same', 'but', 'does', 'still', 'also', 'deep'].forEach(function (key) {
    Object.defineProperty(api, key, { get: function () { return api; } });
  });
  Object.defineProperty(api, 'not', { get: function () { return __astraExpect(actual, !negate); } });

  constProp('true', function () { return actual === true; }, 'Expected true');
  constProp('false', function () { return actual === false; }, 'Expected false');
  constProp('null', function () { return actual === null; }, 'Expected null');
  constProp('undefined', function () { return actual === undefined; }, 'Expected undefined');
  constProp('ok', function () { return !!actual; }, 'Expected a truthy value, got ' + show(actual));
  constProp('exist', function () { return actual !== null && actual !== undefined; }, 'Expected to exist');
  constProp('empty', function () {
    if (actual === null || actual === undefined) return true;
    if (typeof actual === 'string' || Array.isArray(actual)) return actual.length === 0;
    if (typeof actual === 'object') return Object.keys(actual).length === 0;
    return false;
  }, 'Expected to be empty');

  return api;
}

function __astraResponseJson() {
  try {
    return __astraResponse ? JSON.parse(__astraResponse.text()) : null;
  } catch (e) {
    return null;
  }
}

function __astraJsonSegments(expr) {
  var text = String(expr == null ? '' : expr).trim();
  if (text.charAt(0) === '$') text = text.substring(1);
  var segments = [];
  var i = 0;
  while (i < text.length) {
    if (text.substr(i, 2) === '..') {
      i += 2;
      var start = i;
      while (i < text.length && text.charAt(i) !== '.' && text.charAt(i) !== '[') i++;
      var recursiveName = text.substring(start, i).trim();
      if (recursiveName) segments.push({ recursive: recursiveName });
    } else if (text.charAt(i) === '.') {
      i++;
      if (text.charAt(i) === '*') {
        segments.push({ wildcard: true });
        i++;
      } else {
        var start = i;
        while (i < text.length && text.charAt(i) !== '.' && text.charAt(i) !== '[') i++;
        var name = text.substring(start, i).trim();
        if (name) segments.push({ key: name });
      }
    } else if (text.charAt(i) === '[') {
      var end = text.indexOf(']', i);
      if (end < 0) break;
      var raw = text.substring(i + 1, end).trim();
      if (raw === '*') segments.push({ wildcard: true });
      else if (/^-?\d+$/.test(raw)) segments.push({ index: parseInt(raw, 10) });
      else segments.push({ key: raw.replace(/^['"]/, '').replace(/['"]$/, '') });
      i = end + 1;
    } else {
      break;
    }
  }
  return segments;
}

function __astraWalkNamed(node, name, out) {
  if (node === null || typeof node !== 'object') return;
  if (Array.isArray(node)) {
    for (var i = 0; i < node.length; i++) __astraWalkNamed(node[i], name, out);
    return;
  }
  for (var key in node) {
    if (!Object.prototype.hasOwnProperty.call(node, key)) continue;
    if (key === name) out.push(node[key]);
    __astraWalkNamed(node[key], name, out);
  }
}

function __astraJsonPathAll(root, expr) {
  var segments = __astraJsonSegments(expr);
  var current = [root];
  for (var s = 0; s < segments.length; s++) {
    var seg = segments[s];
    var next = [];
    for (var i = 0; i < current.length; i++) {
      var node = current[i];
      if (node === undefined || node === null) continue;
      if (seg.key !== undefined) {
        if (typeof node === 'object' && !Array.isArray(node) &&
            Object.prototype.hasOwnProperty.call(node, seg.key)) {
          next.push(node[seg.key]);
        }
      } else if (seg.index !== undefined) {
        if (Array.isArray(node)) {
          var index = seg.index < 0 ? node.length + seg.index : seg.index;
          if (index >= 0 && index < node.length) next.push(node[index]);
        }
      } else if (seg.wildcard) {
        if (Array.isArray(node)) {
          for (var a = 0; a < node.length; a++) next.push(node[a]);
        } else if (typeof node === 'object') {
          for (var k in node) {
            if (Object.prototype.hasOwnProperty.call(node, k)) next.push(node[k]);
          }
        }
      } else if (seg.recursive !== undefined) {
        __astraWalkNamed(node, seg.recursive, next);
      }
    }
    current = next;
    if (!current.length) break;
  }
  return current.filter(function (item) { return item !== undefined && item !== null; });
}

/// 取单值：只有一个匹配时返回该值，多个返回数组，无匹配返回 undefined。
function __astraJsonPath(root, expr) {
  var all = __astraJsonPathAll(root, expr);
  if (!all.length) return undefined;
  return all.length === 1 ? all[0] : all;
}

function __astraBuildResponse(data) {
  var headerMap = data.headerMap || {};
  var headerList = data.headerList || [];
  __astraResponse = {
    code: data.code,
    status: data.status,
    reason: data.reason,
    responseTime: data.ms,
    responseSize: data.size,
    headers: {
      get: function (name) { return headerMap[String(name).toLowerCase()]; },
      has: function (name) { return headerMap[String(name).toLowerCase()] !== undefined; },
      toObject: function () { return headerMap; },
      all: function () { return headerList; },
      each: function (fn) { headerList.forEach(fn); }
    },
    text: function () { return data.text; },
    json: function () { return JSON.parse(data.text); }
  };
  __astraResponse.to = {
    have: {
      status: function (code) {
        if (__astraResponse.code !== code) {
          throw new Error('Expected status code ' + code + ', got ' + __astraResponse.code);
        }
      },
      header: function (name) {
        if (!__astraResponse.headers.has(name)) throw new Error('Expected response header ' + name);
      },
      body: function (expected) {
        if (__astraResponse.text() !== expected) throw new Error('Response body does not match');
      },
      jsonBody: function (path, value) {
        var body = __astraResponse.json();
        var actual = path;
        if (typeof path === 'string') {
          if (path.charAt(0) === '$') {
            var matches = __astraJsonPathAll(body, path);
            actual = matches.length === 0 ? undefined : (matches.length === 1 ? matches[0] : matches);
          } else {
            actual = path.split('.').reduce(function (node, key) {
              return node == null ? node : node[key];
            }, body);
          }
        }
        if (arguments.length < 2) {
          if (actual === undefined) throw new Error('Expected response JSON to contain ' + path);
          return;
        }
        if (JSON.stringify(actual) !== JSON.stringify(value)) {
          throw new Error('Expected JSON path ' + path + ' to be ' + JSON.stringify(value) +
            ', got ' + JSON.stringify(actual));
        }
      }
    }
  };
  pm.response = __astraResponse;
}

var pm = {
  info: __astraInfo,
  environment: __astraVarStore(function () { return __astraEnv; }),
  variables: __astraVarStore(function () { return __astraVars; }),
  globals: __astraVarStore(function () { return __astraGlobals; }),
  collectionVariables: __astraVarStore(function () { return __astraCollection; }),
  execution: {
    setNextRequest: function (name) {
      __astraNext = name == null ? null : String(name);
    },
    skipRequest: function () {
      __astraNext = null;
      __astraSkip = true;
    }
  },
  request: {
    get method() { return __astraRequest.method; },
    set method(value) { __astraRequest.method = String(value == null ? 'GET' : value).toUpperCase(); },
    get url() { return __astraRequest.url; },
    set url(value) { __astraRequest.url = String(value == null ? '' : value); },
    get headers() { return __astraHeaders; },
    get body() {
      return {
        get mode() { return __astraRequest.bodyMode; },
        set mode(value) { __astraRequest.bodyMode = String(value == null ? '' : value); },
        get raw() { return __astraRequest.body; },
        set raw(value) { __astraRequest.body = String(value == null ? '' : value); },
        toString: function () { return __astraRequest.body; }
      };
    }
  },
  response: null,
  test: function (name, fn) {
    try {
      if (typeof fn === 'function') fn();
      __astraTests.push({ name: String(name), passed: true });
    } catch (e) {
      __astraTests.push({
        name: String(name),
        passed: false,
        error: (e && e.message) ? e.message : String(e)
      });
    }
  },
  expect: function (actual) { return __astraExpect(actual, false); },
  jsonPath: function (expr, node) {
    if (arguments.length > 1) return __astraJsonPath(node, expr);
    return __astraJsonPath(__astraResponseJson(), expr);
  },
  sendRequest: function () {
    __astraPush('warn', ['pm.sendRequest is not supported in this desktop version']);
  }
};

pm.jsonpath = pm.jsonPath;
pm.response = __astraResponse;

function __astraDump() {
  try {
    return JSON.stringify({
      request: {
        method: __astraRequest.method,
        url: __astraRequest.url == null ? '' : String(__astraRequest.url),
        bodyMode: __astraRequest.bodyMode,
        body: __astraRequest.body == null ? '' : String(__astraRequest.body),
        headers: __astraRequest.headers
      },
      env: __astraEnv,
      vars: __astraVars,
      globals: __astraGlobals,
      next: __astraNext,
      logs: __astraLogs,
      tests: __astraTests,
      error: __astraError
    });
  } catch (e) {
    return JSON.stringify({
      error: 'Failed to export script state: ' + ((e && e.message) ? e.message : String(e))
    });
  }
}
''';
}

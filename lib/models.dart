import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

int _idSeq = 0;
final Random _idRandom = Random();

/// 生成唯一 ID。Windows 上系统时钟粒度较粗，同一毫秒内连续创建对象时
/// 仅靠时间戳会重复，因此叠加进程内自增序号与随机后缀。
String newId() {
  _idSeq = (_idSeq + 1) % 0x100000;
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final seq = _idSeq.toRadixString(36).padLeft(3, '0');
  final rnd = _idRandom.nextInt(0x10000).toRadixString(36);
  return '$ts$seq$rnd';
}

class KV {
  bool on;
  String k;
  String v;

  KV({this.on = true, this.k = '', this.v = ''});

  KV copy() => KV(on: on, k: k, v: v);

  Map<String, dynamic> toJson() => {'on': on, 'k': k, 'v': v};

  factory KV.fromJson(Map<String, dynamic> json) => KV(
        on: json['on'] != false,
        k: '${json['k'] ?? ''}',
        v: '${json['v'] ?? ''}',
      );
}

/// 文件上传元数据。真正发送时按 [path] 读取内容，避免把二进制塞进工作区文件。
class UploadFile {
  String name;
  String path;
  String mime;
  int size;
  bool stale;

  UploadFile({
    this.name = '',
    this.path = '',
    this.mime = 'application/octet-stream',
    this.size = 0,
    this.stale = false,
  });

  bool get usable => path.isNotEmpty && !stale;

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': stale ? '' : path,
        'mime': mime,
        'size': size,
        'stale': stale,
      };

  factory UploadFile.fromJson(Map<String, dynamic> json) => UploadFile(
        name: '${json['name'] ?? ''}',
        path: '${json['path'] ?? ''}',
        mime: '${json['mime'] ?? 'application/octet-stream'}',
        size: int.tryParse('${json['size'] ?? 0}') ?? 0,
        stale: json['stale'] == true || '${json['path'] ?? ''}'.isEmpty,
      );
}

class FormRow {
  bool on;
  String k;
  String v;
  String type; // text | file
  UploadFile? file;

  FormRow({
    this.on = true,
    this.k = '',
    this.v = '',
    this.type = 'text',
    this.file,
  });

  Map<String, dynamic> toJson() => {
        'on': on,
        'k': k,
        'v': v,
        'type': type,
        'file': file?.toJson(),
      };

  factory FormRow.fromJson(Map<String, dynamic> json) => FormRow(
        on: json['on'] != false,
        k: '${json['k'] ?? ''}',
        v: '${json['v'] ?? ''}',
        type: '${json['type'] ?? 'text'}',
        file: json['file'] is Map
            ? UploadFile.fromJson(Map<String, dynamic>.from(json['file'] as Map))
            : null,
      );
}

class AuthConfig {
  String type; // none | inherit | bearer | basic | apikey | oauth2
  String token; // bearer token 或 oauth2 获取到的 access_token
  String username;
  String password;
  String apiKeyName;
  String apiKeyValue;
  String apiKeyIn; // header | query
  String oauthTokenUrl;
  String oauthAuthUrl;
  String oauthClientId;
  String oauthClientSecret;
  String oauthScope;
  String oauthGrantType; // client_credentials | password | authorization_code
  String oauthRefreshToken;
  int oauthExpiresAt; // access_token 过期时间（毫秒），0 表示未知
  bool oauthPkce;

  AuthConfig({
    this.type = 'none',
    this.token = '',
    this.username = '',
    this.password = '',
    this.apiKeyName = '',
    this.apiKeyValue = '',
    this.apiKeyIn = 'header',
    this.oauthTokenUrl = '',
    this.oauthAuthUrl = '',
    this.oauthClientId = '',
    this.oauthClientSecret = '',
    this.oauthScope = '',
    this.oauthGrantType = 'client_credentials',
    this.oauthRefreshToken = '',
    this.oauthExpiresAt = 0,
    this.oauthPkce = true,
  });

  bool get oauthExpired =>
      oauthExpiresAt > 0 &&
      DateTime.now().millisecondsSinceEpoch > oauthExpiresAt - 15000;

  AuthConfig copy() => AuthConfig(
        type: type,
        token: token,
        username: username,
        password: password,
        apiKeyName: apiKeyName,
        apiKeyValue: apiKeyValue,
        apiKeyIn: apiKeyIn,
        oauthTokenUrl: oauthTokenUrl,
        oauthAuthUrl: oauthAuthUrl,
        oauthClientId: oauthClientId,
        oauthClientSecret: oauthClientSecret,
        oauthScope: oauthScope,
        oauthGrantType: oauthGrantType,
        oauthRefreshToken: oauthRefreshToken,
        oauthExpiresAt: oauthExpiresAt,
        oauthPkce: oauthPkce,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'token': token,
        'username': username,
        'password': password,
        'apiKeyName': apiKeyName,
        'apiKeyValue': apiKeyValue,
        'apiKeyIn': apiKeyIn,
        'oauthTokenUrl': oauthTokenUrl,
        'oauthAuthUrl': oauthAuthUrl,
        'oauthClientId': oauthClientId,
        'oauthClientSecret': oauthClientSecret,
        'oauthScope': oauthScope,
        'oauthGrantType': oauthGrantType,
        'oauthRefreshToken': oauthRefreshToken,
        'oauthExpiresAt': oauthExpiresAt,
        'oauthPkce': oauthPkce,
      };

  factory AuthConfig.fromJson(Map<String, dynamic> json) => AuthConfig(
        type: '${json['type'] ?? 'none'}',
        token: '${json['token'] ?? ''}',
        username: '${json['username'] ?? ''}',
        password: '${json['password'] ?? ''}',
        apiKeyName: '${json['apiKeyName'] ?? ''}',
        apiKeyValue: '${json['apiKeyValue'] ?? ''}',
        apiKeyIn: '${json['apiKeyIn'] ?? 'header'}',
        oauthTokenUrl: '${json['oauthTokenUrl'] ?? ''}',
        oauthAuthUrl: '${json['oauthAuthUrl'] ?? ''}',
        oauthClientId: '${json['oauthClientId'] ?? ''}',
        oauthClientSecret: '${json['oauthClientSecret'] ?? ''}',
        oauthScope: '${json['oauthScope'] ?? ''}',
        oauthGrantType: '${json['oauthGrantType'] ?? 'client_credentials'}',
        oauthRefreshToken: '${json['oauthRefreshToken'] ?? ''}',
        oauthExpiresAt: int.tryParse('${json['oauthExpiresAt'] ?? 0}') ?? 0,
        oauthPkce: json['oauthPkce'] != false,
      );
}

class RequestOptions {
  bool followRedirects;
  bool rejectUnauthorized;
  bool manageCookies;
  bool streamSse;
  int timeoutSeconds; // 0 表示不限制

  RequestOptions({
    this.followRedirects = true,
    this.rejectUnauthorized = true,
    this.manageCookies = true,
    this.streamSse = false,
    this.timeoutSeconds = 90,
  });

  Map<String, dynamic> toJson() => {
        'followRedirects': followRedirects,
        'rejectUnauthorized': rejectUnauthorized,
        'manageCookies': manageCookies,
        'streamSse': streamSse,
        'timeoutSeconds': timeoutSeconds,
      };

  factory RequestOptions.fromJson(Map<String, dynamic> json) => RequestOptions(
        followRedirects: json['followRedirects'] != false,
        rejectUnauthorized: json['rejectUnauthorized'] != false,
        manageCookies: json['manageCookies'] != false,
        streamSse: json['streamSse'] == true,
        timeoutSeconds: int.tryParse('${json['timeoutSeconds'] ?? 90}') ?? 90,
      );
}

class ApiRequest {
  String method;
  String url;
  List<KV> params;
  List<KV> headers;
  String bodyMode; // none | json | text | form | form-data | graphql | grpc
  String body;
  List<KV> form;
  List<FormRow> formData;
  String preScript;
  String postScript;
  String graphqlQuery;
  String graphqlVars;
  String grpcPayload; // base64 或 JSON
  bool grpcBinary; // true = payload 为 base64 protobuf，false = JSON
  AuthConfig auth;
  RequestOptions options;

  ApiRequest({
    this.method = 'GET',
    this.url = '',
    List<KV>? params,
    List<KV>? headers,
    this.bodyMode = 'none',
    this.body = '',
    List<KV>? form,
    List<FormRow>? formData,
    this.preScript = '',
    this.postScript = '',
    this.graphqlQuery = '',
    this.graphqlVars = '',
    this.grpcPayload = '',
    this.grpcBinary = true,
    AuthConfig? auth,
    RequestOptions? options,
  })  : params = params ?? [KV()],
        headers = headers ?? [KV()],
        form = form ?? [KV()],
        formData = formData ?? [FormRow()],
        auth = auth ?? AuthConfig(),
        options = options ?? RequestOptions();

  ApiRequest copy() => ApiRequest(
        method: method,
        url: url,
        params: params.map((e) => e.copy()).toList(),
        headers: headers.map((e) => e.copy()).toList(),
        bodyMode: bodyMode,
        body: body,
        form: form.map((e) => e.copy()).toList(),
        formData: formData
            .map((e) => FormRow(
                  on: e.on,
                  k: e.k,
                  v: e.v,
                  type: e.type,
                  file: e.file == null
                      ? null
                      : UploadFile(
                          name: e.file!.name,
                          path: e.file!.path,
                          mime: e.file!.mime,
                          size: e.file!.size,
                          stale: e.file!.stale,
                        ),
                ))
            .toList(),
        preScript: preScript,
        postScript: postScript,
        graphqlQuery: graphqlQuery,
        graphqlVars: graphqlVars,
        grpcPayload: grpcPayload,
        grpcBinary: grpcBinary,
        auth: auth.copy(),
        options: RequestOptions(
          followRedirects: options.followRedirects,
          rejectUnauthorized: options.rejectUnauthorized,
          manageCookies: options.manageCookies,
          streamSse: options.streamSse,
          timeoutSeconds: options.timeoutSeconds,
        ),
      );

  Map<String, dynamic> toJson() => {
        'method': method,
        'url': url,
        'params': params.map((e) => e.toJson()).toList(),
        'headers': headers.map((e) => e.toJson()).toList(),
        'bodyMode': bodyMode,
        'body': body,
        'form': form.map((e) => e.toJson()).toList(),
        'formData': formData.map((e) => e.toJson()).toList(),
        'scripts': {'pre': preScript, 'post': postScript},
        'graphql': {'query': graphqlQuery, 'variables': graphqlVars},
        'grpc': {'payload': grpcPayload, 'binary': grpcBinary},
        'auth': auth.toJson(),
        'options': options.toJson(),
      };

  factory ApiRequest.fromJson(Map<String, dynamic> json) {
    final scripts = json['scripts'] is Map ? json['scripts'] as Map : {};
    final graphql = json['graphql'] is Map ? json['graphql'] as Map : {};
    final grpc = json['grpc'] is Map ? json['grpc'] as Map : {};
    return ApiRequest(
      method: '${json['method'] ?? 'GET'}',
      url: '${json['url'] ?? ''}',
      params: _kvList(json['params']),
      headers: _kvList(json['headers']),
      bodyMode: '${json['bodyMode'] ?? 'none'}',
      body: '${json['body'] ?? ''}',
      form: _kvList(json['form']),
      formData: _formList(json['formData']),
      preScript: '${scripts['pre'] ?? ''}',
      postScript: '${scripts['post'] ?? ''}',
      graphqlQuery: '${graphql['query'] ?? ''}',
      graphqlVars: '${graphql['variables'] ?? ''}',
      grpcPayload: '${grpc['payload'] ?? ''}',
      grpcBinary: grpc['binary'] != false,
      auth: json['auth'] is Map
          ? AuthConfig.fromJson(Map<String, dynamic>.from(json['auth'] as Map))
          : AuthConfig(),
      options: json['options'] is Map
          ? RequestOptions.fromJson(Map<String, dynamic>.from(json['options'] as Map))
          : RequestOptions(),
    );
  }

  static List<KV> _kvList(dynamic raw) {
    if (raw is! List || raw.isEmpty) return [KV()];
    return raw
        .whereType<Map>()
        .map((e) => KV.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static List<FormRow> _formList(dynamic raw) {
    if (raw is! List || raw.isEmpty) return [FormRow()];
    return raw
        .whereType<Map>()
        .map((e) => FormRow.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

class WsConfig {
  String url;
  List<KV> headers;
  String subprotocol;
  bool verify;

  WsConfig({
    this.url = '',
    List<KV>? headers,
    this.subprotocol = '',
    this.verify = true,
  }) : headers = headers ?? [KV()];

  WsConfig copy() => WsConfig(
        url: url,
        headers: headers.map((e) => e.copy()).toList(),
        subprotocol: subprotocol,
        verify: verify,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'headers': headers.map((e) => e.toJson()).toList(),
        'subprotocol': subprotocol,
        'verify': verify,
      };

  factory WsConfig.fromJson(Map<String, dynamic> json) => WsConfig(
        url: '${json['url'] ?? ''}',
        headers: json['headers'] is List
            ? (json['headers'] as List)
                .whereType<Map>()
                .map((e) => KV.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [KV()],
        subprotocol: '${json['subprotocol'] ?? ''}',
        verify: json['verify'] != false,
      );
}

/// 右侧编辑器中的一个标签页：可以绑定已保存的请求，也可以是未保存的草稿。
class WorkspaceTab {
  String id;
  String entryId; // 已保存条目 id，草稿为空
  String historyId; // 从历史记录打开时记录来源 id，便于去重
  String name;
  String mode; // http | ws
  String groupId;
  String folderId;
  ApiRequest request;
  WsConfig ws;

  WorkspaceTab({
    String? id,
    this.entryId = '',
    this.historyId = '',
    this.name = '未命名 API',
    this.mode = 'http',
    this.groupId = '',
    this.folderId = '',
    ApiRequest? request,
    WsConfig? ws,
  })  : id = id ?? newId(),
        request = request ?? ApiRequest(),
        ws = ws ?? WsConfig();

  Map<String, dynamic> toJson() => {
        'id': id,
        'entryId': entryId,
        'historyId': historyId,
        'name': name,
        'mode': mode,
        'groupId': groupId,
        'folderId': folderId,
        'request': request.toJson(),
        'ws': ws.toJson(),
      };

  factory WorkspaceTab.fromJson(Map<String, dynamic> json) => WorkspaceTab(
        id: '${json['id'] ?? newId()}',
        entryId: '${json['entryId'] ?? ''}',
        historyId: '${json['historyId'] ?? ''}',
        name: '${json['name'] ?? '未命名 API'}',
        mode: '${json['mode'] ?? 'http'}',
        groupId: '${json['groupId'] ?? ''}',
        folderId: '${json['folderId'] ?? ''}',
        request: json['request'] is Map
            ? ApiRequest.fromJson(Map<String, dynamic>.from(json['request'] as Map))
            : null,
        ws: json['ws'] is Map
            ? WsConfig.fromJson(Map<String, dynamic>.from(json['ws'] as Map))
            : null,
      );
}

class CollectionEntry {
  String id;
  String name;
  String mode; // http | ws
  String groupId;
  String folderId;
  String description;
  List<KV> variables;
  ApiRequest? request;
  WsConfig? ws;
  int ts;
  List<RequestExample> examples;

  CollectionEntry({
    String? id,
    this.name = '未命名请求',
    this.mode = 'http',
    this.groupId = '',
    this.folderId = '',
    this.description = '',
    List<KV>? variables,
    this.request,
    this.ws,
    int? ts,
    List<RequestExample>? examples,
  })  : id = id ?? newId(),
        variables = variables ?? [],
        examples = examples ?? [],
        ts = ts ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode,
        'groupId': groupId,
        'folderId': folderId,
        'description': description,
        'variables': variables.map((e) => e.toJson()).toList(),
        'request': request?.toJson(),
        'ws': ws?.toJson(),
        'ts': ts,
        'examples': examples.map((e) => e.toJson()).toList(),
      };

  factory CollectionEntry.fromJson(Map<String, dynamic> json) => CollectionEntry(
        id: '${json['id'] ?? newId()}',
        name: '${json['name'] ?? '未命名请求'}',
        mode: '${json['mode'] ?? 'http'}',
        groupId: '${json['groupId'] ?? ''}',
        folderId: '${json['folderId'] ?? ''}',
        description: '${json['description'] ?? ''}',
        variables: json['variables'] is List
            ? (json['variables'] as List)
                .whereType<Map>()
                .map((e) => KV.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [],
        request: json['request'] is Map
            ? ApiRequest.fromJson(Map<String, dynamic>.from(json['request'] as Map))
            : null,
        ws: json['ws'] is Map
            ? WsConfig.fromJson(Map<String, dynamic>.from(json['ws'] as Map))
            : null,
        ts: int.tryParse('${json['ts'] ?? 0}') ?? 0,
        examples: json['examples'] is List
            ? (json['examples'] as List)
                .whereType<Map>()
                .map((e) => RequestExample.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [],
      );
}

/// 保存的响应示例，方便回归时对照。
class RequestExample {
  String id;
  String name;
  int status;
  String body;
  Map<String, List<String>> headers;
  int ts;

  RequestExample({
    String? id,
    this.name = '示例',
    this.status = 200,
    this.body = '',
    Map<String, List<String>>? headers,
    int? ts,
  })  : id = id ?? newId(),
        headers = headers ?? {},
        ts = ts ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'body': body,
        'headers': headers,
        'ts': ts,
      };

  factory RequestExample.fromJson(Map<String, dynamic> json) => RequestExample(
        id: '${json['id'] ?? newId()}',
        name: '${json['name'] ?? '示例'}',
        status: int.tryParse('${json['status'] ?? 200}') ?? 200,
        body: '${json['body'] ?? ''}',
        headers: json['headers'] is Map
            ? (json['headers'] as Map).map((key, value) => MapEntry(
                  '$key',
                  value is List ? value.map((e) => '$e').toList() : ['$value'],
                ))
            : {},
        ts: int.tryParse('${json['ts'] ?? 0}') ?? 0,
      );
}

/// 集合内的文件夹，可无限层级嵌套。
class CollectionFolder {
  String id;
  String groupId;
  String parentId;
  String name;
  String description;
  bool expanded;
  List<KV> variables;
  AuthConfig auth;

  CollectionFolder({
    String? id,
    this.groupId = '',
    this.parentId = '',
    this.name = '新建文件夹',
    this.description = '',
    this.expanded = true,
    List<KV>? variables,
    AuthConfig? auth,
  })  : id = id ?? newId(),
        variables = variables ?? [],
        auth = auth ?? AuthConfig(type: 'inherit');

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'parentId': parentId,
        'name': name,
        'description': description,
        'expanded': expanded,
        'variables': variables.map((e) => e.toJson()).toList(),
        'auth': auth.toJson(),
      };

  factory CollectionFolder.fromJson(Map<String, dynamic> json) => CollectionFolder(
        id: '${json['id'] ?? newId()}',
        groupId: '${json['groupId'] ?? ''}',
        parentId: '${json['parentId'] ?? ''}',
        name: '${json['name'] ?? '新建文件夹'}',
        description: '${json['description'] ?? ''}',
        expanded: json['expanded'] != false,
        variables: json['variables'] is List
            ? (json['variables'] as List)
                .whereType<Map>()
                .map((e) => KV.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [],
        auth: json['auth'] is Map
            ? AuthConfig.fromJson(Map<String, dynamic>.from(json['auth'] as Map))
            : AuthConfig(type: 'inherit'),
      );
}

/// 集合（分组）：用于把同类的 HTTP 请求或 WebSocket 连接归档到一起。
class CollectionGroup {
  String id;
  String name;
  String mode; // http | ws
  String description;
  bool expanded;
  List<KV> variables;
  AuthConfig auth;

  CollectionGroup({
    String? id,
    this.name = '新建集合',
    this.mode = 'http',
    this.description = '',
    this.expanded = true,
    List<KV>? variables,
    AuthConfig? auth,
  })  : id = id ?? newId(),
        variables = variables ?? [],
        auth = auth ?? AuthConfig();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode,
        'description': description,
        'expanded': expanded,
        'variables': variables.map((e) => e.toJson()).toList(),
        'auth': auth.toJson(),
      };

  factory CollectionGroup.fromJson(Map<String, dynamic> json) => CollectionGroup(
        id: '${json['id'] ?? newId()}',
        name: '${json['name'] ?? '新建集合'}',
        mode: '${json['mode'] ?? 'http'}',
        description: '${json['description'] ?? ''}',
        expanded: json['expanded'] != false,
        variables: json['variables'] is List
            ? (json['variables'] as List)
                .whereType<Map>()
                .map((e) => KV.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [],
        auth: json['auth'] is Map
            ? AuthConfig.fromJson(Map<String, dynamic>.from(json['auth'] as Map))
            : AuthConfig(),
      );
}

class Env {
  String id;
  String name;
  List<KV> vars;

  Env({String? id, this.name = '默认环境', List<KV>? vars})
      : id = id ?? newId(),
        vars = vars ?? [KV()];

  Env copy() => Env(id: id, name: name, vars: vars.map((e) => e.copy()).toList());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'vars': vars.map((e) => e.toJson()).toList(),
      };

  factory Env.fromJson(Map<String, dynamic> json) => Env(
        id: json['id'] == null ? null : '${json['id']}',
        name: '${json['name'] ?? '默认环境'}',
        vars: json['vars'] is List
            ? (json['vars'] as List)
                .whereType<Map>()
                .map((e) => KV.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [KV()],
      );
}

class CookieEntry {
  String name;
  String value;
  String domain;
  String path;
  int expires; // 0 = session
  bool secure;
  bool httpOnly;

  CookieEntry({
    this.name = '',
    this.value = '',
    this.domain = '',
    this.path = '/',
    this.expires = 0,
    this.secure = false,
    this.httpOnly = false,
  });

  bool get expired =>
      expires > 0 && DateTime.now().millisecondsSinceEpoch > expires;

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'expires': expires,
        'secure': secure,
        'httpOnly': httpOnly,
      };

  factory CookieEntry.fromJson(Map<String, dynamic> json) => CookieEntry(
        name: '${json['name'] ?? ''}',
        value: '${json['value'] ?? ''}',
        domain: '${json['domain'] ?? ''}',
        path: '${json['path'] ?? '/'}',
        expires: int.tryParse('${json['expires'] ?? 0}') ?? 0,
        secure: json['secure'] == true,
        httpOnly: json['httpOnly'] == true,
      );
}

class HistoryEntry {
  String id;
  String mode;
  String name;
  String method;
  String url;
  int? status;
  int ms;
  int ts;
  ApiRequest? snapshot;
  WsConfig? wsSnapshot;

  HistoryEntry({
    String? id,
    this.mode = 'http',
    this.name = '',
    this.method = 'GET',
    this.url = '',
    this.status,
    this.ms = 0,
    int? ts,
    this.snapshot,
    this.wsSnapshot,
  })  : id = id ?? newId(),
        ts = ts ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': mode,
        'name': name,
        'method': method,
        'url': url,
        'status': status,
        'ms': ms,
        'ts': ts,
        'request': snapshot?.toJson(),
        'ws': wsSnapshot?.toJson(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: '${json['id'] ?? newId()}',
        mode: '${json['mode'] ?? 'http'}',
        name: '${json['name'] ?? ''}',
        method: '${json['method'] ?? 'GET'}',
        url: '${json['url'] ?? ''}',
        status: json['status'] == null ? null : int.tryParse('${json['status']}'),
        ms: int.tryParse('${json['ms'] ?? 0}') ?? 0,
        ts: int.tryParse('${json['ts'] ?? 0}') ?? 0,
        snapshot: json['request'] is Map
            ? ApiRequest.fromJson(Map<String, dynamic>.from(json['request'] as Map))
            : null,
        wsSnapshot: json['ws'] is Map
            ? WsConfig.fromJson(Map<String, dynamic>.from(json['ws'] as Map))
            : null,
      );
}

class HttpResult {
  final int status;
  final String reason;
  final Map<String, List<String>> headers;
  final Uint8List bytes;
  final String? text;
  final int ms;
  final int size;

  HttpResult({
    required this.status,
    required this.reason,
    required this.headers,
    required this.bytes,
    required this.text,
    required this.ms,
    required this.size,
  });

  String? header(String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) {
        return entry.value.join(', ');
      }
    }
    return null;
  }

  bool get isText {
    if (text != null) return true;
    final type = (header('content-type') ?? '').toLowerCase();
    return type.contains('json') ||
        type.contains('text') ||
        type.contains('xml') ||
        type.contains('javascript') ||
        type.contains('x-www-form-urlencoded');
  }

  String get prettyBody {
    final raw = text;
    if (raw == null) return '';
    final type = (header('content-type') ?? '').toLowerCase();
    if (!type.contains('json') && !raw.trimLeft().startsWith('{') && !raw.trimLeft().startsWith('[')) {
      return raw;
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'reason': reason,
        'headers': headers,
        'ms': ms,
        'size': size,
        'text': text,
      };
}

class WsMessage {
  final bool outgoing;
  final String text;
  final DateTime time;
  final bool system;

  WsMessage(this.text, {this.outgoing = false, this.system = false, DateTime? time})
      : time = time ?? DateTime.now();
}

/// 全局代理与客户端证书配置（对所有请求生效）。
class AppSettings {
  String proxyUrl; // http://127.0.0.1:8080，留空表示直连
  String proxyBypass; // 逗号 / 空格分隔的主机列表
  String certPath;
  String keyPath;
  String keyPassword;
  bool verifyTls;

  AppSettings({
    this.proxyUrl = '',
    this.proxyBypass = '',
    this.certPath = '',
    this.keyPath = '',
    this.keyPassword = '',
    this.verifyTls = true,
  });

  bool get proxyEnabled => proxyUrl.trim().isNotEmpty;
  bool get hasClientCert => certPath.trim().isNotEmpty && keyPath.trim().isNotEmpty;

  AppSettings copy() => AppSettings(
        proxyUrl: proxyUrl,
        proxyBypass: proxyBypass,
        certPath: certPath,
        keyPath: keyPath,
        keyPassword: keyPassword,
        verifyTls: verifyTls,
      );

  Map<String, dynamic> toJson() => {
        'proxyUrl': proxyUrl,
        'proxyBypass': proxyBypass,
        'certPath': certPath,
        'keyPath': keyPath,
        'keyPassword': keyPassword,
        'verifyTls': verifyTls,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        proxyUrl: '${json['proxyUrl'] ?? ''}',
        proxyBypass: '${json['proxyBypass'] ?? ''}',
        certPath: '${json['certPath'] ?? ''}',
        keyPath: '${json['keyPath'] ?? ''}',
        keyPassword: '${json['keyPassword'] ?? ''}',
        verifyTls: json['verifyTls'] != false,
      );
}

/// 集合运行器中的单次请求结果。
class RunStepResult {
  final String entryId;
  final String name;
  final String method;
  final String url;
  final int? status;
  final int ms;
  final int iteration;
  final List<String> failures;
  final String? error;
  final String body;

  RunStepResult({
    required this.entryId,
    required this.name,
    required this.method,
    required this.url,
    required this.status,
    required this.ms,
    required this.iteration,
    required this.failures,
    required this.error,
    required this.body,
  });

  bool get passed => error == null && failures.isEmpty && status != null && status! < 400;

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'name': name,
        'method': method,
        'url': url,
        'status': status,
        'ms': ms,
        'iteration': iteration,
        'failures': failures,
        'error': error,
      };
}

/// 一次集合运行的汇总报告。
class RunReport {
  final String id;
  final String collectionName;
  final DateTime startedAt;
  final int durationMs;
  final int iterations;
  final List<RunStepResult> steps;
  final bool cancelled;
  final String? dataSource;

  RunReport({
    String? id,
    required this.collectionName,
    required this.startedAt,
    required this.durationMs,
    required this.iterations,
    required this.steps,
    this.cancelled = false,
    this.dataSource,
  }) : id = id ?? newId();

  int get total => steps.length;
  int get passed => steps.where((step) => step.passed).length;
  int get failed => total - passed;
  double get passRate => total == 0 ? 0 : passed / total;
  int get totalMs => steps.fold(0, (sum, step) => sum + step.ms);

  Map<String, dynamic> toJson() => {
        'id': id,
        'collection': collectionName,
        'startedAt': startedAt.toIso8601String(),
        'durationMs': durationMs,
        'iterations': iterations,
        'cancelled': cancelled,
        'dataSource': dataSource,
        'total': total,
        'passed': passed,
        'failed': failed,
        'passRate': passRate,
        'steps': steps.map((step) => step.toJson()).toList(),
      };
}

/// 定时监控：按固定间隔在本地运行集合。
class MonitorConfig {
  String id;
  String groupId;
  String name;
  int intervalMinutes;
  int iterations;
  bool enabled;
  int lastRunAt; // 毫秒，0 表示从未运行
  int lastPassed;
  int lastTotal;
  String lastError;

  MonitorConfig({
    String? id,
    this.groupId = '',
    this.name = '定时监控',
    this.intervalMinutes = 30,
    this.iterations = 1,
    this.enabled = false,
    this.lastRunAt = 0,
    this.lastPassed = 0,
    this.lastTotal = 0,
    this.lastError = '',
  }) : id = id ?? newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'name': name,
        'intervalMinutes': intervalMinutes,
        'iterations': iterations,
        'enabled': enabled,
        'lastRunAt': lastRunAt,
        'lastPassed': lastPassed,
        'lastTotal': lastTotal,
        'lastError': lastError,
      };

  factory MonitorConfig.fromJson(Map<String, dynamic> json) => MonitorConfig(
        id: '${json['id'] ?? newId()}',
        groupId: '${json['groupId'] ?? ''}',
        name: '${json['name'] ?? '定时监控'}',
        intervalMinutes: int.tryParse('${json['intervalMinutes'] ?? 30}') ?? 30,
        iterations: int.tryParse('${json['iterations'] ?? 1}') ?? 1,
        enabled: json['enabled'] == true,
        lastRunAt: int.tryParse('${json['lastRunAt'] ?? 0}') ?? 0,
        lastPassed: int.tryParse('${json['lastPassed'] ?? 0}') ?? 0,
        lastTotal: int.tryParse('${json['lastTotal'] ?? 0}') ?? 0,
        lastError: '${json['lastError'] ?? ''}',
      );
}

/// 变量面板中的一层作用域。
class VariableScope {
  final String label;
  final List<KV> vars;

  const VariableScope(this.label, this.vars);
}

/// SSE 事件流中的一条消息。
class SseEvent {
  final String event;
  final String data;
  final String? id;
  final DateTime time;

  SseEvent({
    this.event = 'message',
    this.data = '',
    this.id,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}

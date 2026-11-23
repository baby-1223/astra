import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:astra/models.dart';
import 'package:astra/services/api_service.dart';
import 'package:astra/services/converters.dart';
import 'package:astra/services/ws_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HttpService', () {
    late HttpServer server;
    late String base;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/json') {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"ok":true,"name":"Astra"}');
        } else if (path == '/cookie') {
          request.response.cookies.add(Cookie('sid', 'abc123')..path = '/');
          request.response.write('cookie set');
        } else if (path == '/echo') {
          final body = await utf8.decoder.bind(request).join();
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'method': request.method,
            'body': body,
            'cookie': request.headers.value('cookie'),
            'contentType': request.headers.contentType?.mimeType,
          }));
        } else {
          request.response.statusCode = 404;
          request.response.write('not found');
        }
        await request.response.close();
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    test('GET JSON response and timing', () async {
      final service = HttpService();
      final result = await service.send(
        method: 'GET',
        url: '$base/json',
        headers: {},
        body: '',
        multipart: const [],
        followRedirects: true,
        rejectUnauthorized: true,
        cookies: [],
      );
      expect(result.status, 200);
      expect(result.prettyBody.contains('"ok": true'), isTrue);
      expect(result.ms >= 0, isTrue);
      expect(result.size > 0, isTrue);
    });

    test('POST JSON body', () async {
      final service = HttpService();
      final result = await service.send(
        method: 'POST',
        url: '$base/echo',
        headers: {'Content-Type': 'application/json'},
        body: '{"hello":"astra"}',
        multipart: const [],
        followRedirects: true,
        rejectUnauthorized: true,
        cookies: [],
      );
      final data = jsonDecode(result.text!) as Map<String, dynamic>;
      expect(data['method'], 'POST');
      expect(data['body'], '{"hello":"astra"}');
      expect(data['contentType'], 'application/json');
    });

    test('cookies are stored and replayed', () async {
      final service = HttpService();
      final jar = <CookieEntry>[];
      await service.send(
        method: 'GET',
        url: '$base/cookie',
        headers: {},
        body: '',
        multipart: const [],
        followRedirects: true,
        rejectUnauthorized: true,
        cookies: jar,
      );
      expect(jar.any((item) => item.name == 'sid' && item.value == 'abc123'), isTrue);

      final echoed = await service.send(
        method: 'GET',
        url: '$base/echo',
        headers: {},
        body: '',
        multipart: const [],
        followRedirects: true,
        rejectUnauthorized: true,
        cookies: jar,
      );
      final data = jsonDecode(echoed.text!) as Map<String, dynamic>;
      expect(data['cookie'], contains('sid=abc123'));
    });

    test('multipart upload includes file and text fields', () async {
      final temp = File('${Directory.systemTemp.path}/astra-test-upload.txt');
      await temp.writeAsString('astra-file-content');
      final service = HttpService();
      final result = await service.send(
        method: 'POST',
        url: '$base/echo',
        headers: {},
        body: '',
        multipart: [
          FormRow(k: 'name', v: 'astra'),
          FormRow(
            k: 'file',
            type: 'file',
            file: UploadFile(name: 'test.txt', path: temp.path, mime: 'text/plain'),
          ),
        ],
        followRedirects: true,
        rejectUnauthorized: true,
        cookies: [],
      );
      final data = jsonDecode(result.text!) as Map<String, dynamic>;
      expect(data['contentType'], 'multipart/form-data');
      expect(data['body'], contains('astra-file-content'));
      expect(data['body'], contains('filename="test.txt"'));
      expect(data['body'], contains('astra'));
    });
  });

  group('WsService', () {
    test('connects, sends and receives messages', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          request.response.statusCode = 400;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((data) {
          socket.add('echo:${data}');
        });
      });

      final service = WsService();
      final received = <String>[];
      final opened = Completer<void>();
      await service.connect(
        url: 'ws://127.0.0.1:${server.port}/ws',
        headers: {'X-Astra': 'test'},
        subprotocol: '',
        verify: true,
        onOpen: opened.complete,
        onMessage: (data) => received.add('$data'),
        onClose: (_) {},
        onError: (_) {},
      );
      await opened.future.timeout(const Duration(seconds: 3));
      service.send('hello');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(received, contains('echo:hello'));
      await service.close();
      await server.close(force: true);
    });
  });

  group('Converters', () {
    const postman = {
      'info': {'name': 'Demo', 'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json'},
      'variable': [
        {'key': 'baseUrl', 'value': 'https://api.demo.com'},
      ],
      'item': [
        {
          'name': '用户',
          'item': [
            {
              'name': '获取用户',
              'request': {
                'method': 'GET',
                'header': [
                  {'key': 'Accept', 'value': 'application/json'},
                ],
                'url': {
                  'raw': '{{baseUrl}}/users/:id',
                  'host': ['{{baseUrl}}'],
                  'path': ['users', ':id'],
                  'query': [
                    {'key': 'page', 'value': '1'},
                  ],
                },
              },
            },
          ],
        },
        {
          'name': '创建用户',
          'request': {
            'method': 'POST',
            'url': '{{baseUrl}}/users',
            'body': {
              'mode': 'raw',
              'raw': '{"name":"Astra"}',
              'options': {'raw': {'language': 'json'}},
            },
            'auth': {
              'type': 'bearer',
              'bearer': [
                {'key': 'token', 'value': '{{token}}'},
              ],
            },
          },
        },
      ],
    };

    test('imports Postman folders and variables', () {
      expect(detectKind(postman), 'postman');
      final result = importPostman(Map<String, dynamic>.from(postman));
      expect(result.collections.length, 2);
      expect(result.collections.first.name, '用户 / 获取用户');
      expect(result.variables.any((item) => item.k == 'baseUrl'), isTrue);
      expect(result.collections[1].request!.bodyMode, 'json');
      expect(result.collections[1].request!.auth.type, 'bearer');
    });

    test('imports Postman data dumps with every collection and environment', () {
      final dump = {
        'version': 1,
        'collections': [
          {
            'name': 'Team API',
            'variable': [
              {'key': 'teamToken', 'value': 'abc', 'enabled': true},
            ],
            'requests': [
              {
                'name': 'Ping',
                'method': 'get',
                'url': 'https://api.test/ping',
                'headers': 'X-Team: astra\n',
              },
            ],
            'folders': [
              {
                'name': 'Auth',
                'folders': <dynamic>[],
                'requests': [
                  {
                    'name': 'Login',
                    'method': 'post',
                    'url': 'https://api.test/login',
                    'headers': 'Content-Type: application/json\n',
                    'dataMode': 'raw',
                    'data': '{"user":"ada"}',
                    'currentHelper': 'bearerAuth',
                    'helperAttributes': {'token': '{{token}}'},
                  },
                ],
              },
            ],
          },
          {
            'info': {'name': 'V2'},
            'item': [
              {
                'name': 'Users',
                'item': [
                  {
                    'name': 'List',
                    'request': {'method': 'GET', 'url': 'https://api.test/users'},
                  },
                ],
              },
            ],
          },
        ],
        'environments': [
          {
            'name': 'Dev',
            'values': [
              {'key': 'baseUrl', 'value': 'https://api.test', 'enabled': true},
            ],
          },
        ],
        'globals': [
          {'key': 'team', 'value': 'astra', 'enabled': true},
          {'key': 'off', 'value': 'x', 'enabled': false},
        ],
      };

      expect(detectKind(dump), 'postman');
      final result = importPostman(Map<String, dynamic>.from(dump));

      expect(result.collections.length, 3);
      expect(result.groups.map((g) => g.name), containsAll(['Team API', 'V2']));

      final team = result.groups.firstWhere((g) => g.name == 'Team API');
      expect(team.variables.single.k, 'teamToken');
      expect(team.variables.single.v, 'abc');
      final folder = result.folders.firstWhere((f) => f.name == 'Auth');
      expect(folder.groupId, team.id);
      expect(folder.parentId, '');

      final ping = result.collections.firstWhere((c) => c.name == 'Ping');
      expect(ping.groupId, team.id);
      expect(ping.folderId, '');
      expect(ping.request!.headers.first.k, 'X-Team');

      final login = result.collections.firstWhere((c) => c.name == 'Login');
      expect(login.groupId, team.id);
      expect(login.folderId, folder.id);
      expect(login.request!.bodyMode, 'json');
      expect(login.request!.auth.type, 'bearer');
      expect(login.request!.auth.token, '{{token}}');

      final v2 = result.groups.firstWhere((g) => g.name == 'V2');
      final usersFolder = result.folders.firstWhere((f) => f.name == 'Users');
      final list = result.collections.firstWhere((c) => c.name == 'List');
      expect(usersFolder.groupId, v2.id);
      expect(list.groupId, v2.id);
      expect(list.folderId, usersFolder.id);

      final environment = result.environments.single;
      expect(environment.name, 'Dev');
      expect(environment.vars.first.k, 'baseUrl');
      expect(environment.vars.first.v, 'https://api.test');
      expect(result.globals.map((g) => g.k), ['team']);
      expect(result.variables, isEmpty);
    });

    test('v2.1 dump keeps nested folders', () {
      final dump = {
        'version': 1,
        'collections': [
          {
            'info': {'name': 'Shop', 'schema': 'v2.1.0'},
            'item': [
              {
                'name': 'Auth',
                'item': [
                  {
                    'name': 'Token',
                    'request': {
                      'method': 'POST',
                      'url': {'raw': 'https://api.test/token'},
                    },
                  },
                  {
                    'name': 'Deep',
                    'item': [
                      {
                        'name': 'Ping',
                        'request': {'method': 'GET', 'url': 'https://api.test/ping'},
                      },
                    ],
                  },
                ],
              },
              {
                'name': 'Root',
                'request': {'method': 'GET', 'url': 'https://api.test/root'},
              },
            ],
          },
        ],
      };

      final result = importPostman(Map<String, dynamic>.from(dump));

      expect(result.groups.single.name, 'Shop');
      final auth = result.folders.firstWhere((f) => f.name == 'Auth');
      final deep = result.folders.firstWhere((f) => f.name == 'Deep');
      expect(auth.parentId, '');
      expect(deep.parentId, auth.id);
      expect(result.collections.firstWhere((c) => c.name == 'Token').folderId, auth.id);
      expect(result.collections.firstWhere((c) => c.name == 'Ping').folderId, deep.id);
      expect(result.collections.firstWhere((c) => c.name == 'Root').folderId, '');
      expect(
        result.collections.every((c) => c.groupId == result.groups.single.id),
        isTrue,
      );
    });

    test('exports Postman and OpenAPI', () {
      final result = importPostman(Map<String, dynamic>.from(postman));
      final env = Env(vars: [KV(k: 'baseUrl', v: 'https://api.demo.com')]);
      final exported = toPostman(result.collections, env);
      expect((exported['item'] as List).length, 2);
      expect(exported['variable'], isA<List>());

      final openapi = toOpenApi(result.collections, env);
      final paths = openapi['paths'] as Map<String, dynamic>;
      expect(paths.containsKey('/users/:id'), isTrue);
      expect((openapi['servers'] as List).length, greaterThan(0));
    });

    test('imports OpenAPI 3 paths and body', () {
      final doc = <String, dynamic>{
        'openapi': '3.0.3',
        'info': {'title': 'Demo API'},
        'servers': [
          {'url': 'https://api.demo.com/v1'},
        ],
        'paths': {
          '/pets/{petId}': {
            'get': {
              'summary': '读取宠物',
              'parameters': [
                {'name': 'petId', 'in': 'path', 'required': true, 'schema': {'type': 'string'}},
                {'name': 'verbose', 'in': 'query', 'schema': {'type': 'boolean', 'default': false}},
              ],
              'responses': {'200': {'description': 'OK'}},
            },
            'post': {
              'summary': '更新宠物',
              'requestBody': {
                'content': {
                  'application/json': {
                    'schema': {
                      'type': 'object',
                      'properties': {
                        'name': {'type': 'string', 'example': 'Milo'},
                        'age': {'type': 'integer'},
                      },
                    },
                  },
                },
              },
              'responses': {'200': {'description': 'OK'}},
            },
          },
        },
      };
      expect(detectKind(doc), 'openapi');
      final result = importOpenApi(doc);
      expect(result.collections.length, 2);
      final get = result.collections.firstWhere((item) => item.request!.method == 'GET');
      expect(get.request!.url, 'https://api.demo.com/v1/pets/{{petId}}');
      final post = result.collections.firstWhere((item) => item.request!.method == 'POST');
      expect(post.request!.bodyMode, 'json');
      expect(post.request!.body, contains('Milo'));
    });
  });
}

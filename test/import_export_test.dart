import 'package:astra/models.dart';
import 'package:astra/services/converters.dart';
import 'package:astra/services/runner_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Insomnia import', () {
    final export = {
      '_type': 'export',
      '__export_format': 4,
      'resources': [
        {'_id': 'wrk_1', '_type': 'workspace', 'name': 'Demo'},
        {
          '_id': 'fld_1',
          '_type': 'request_group',
          'parentId': 'wrk_1',
          'name': 'Users',
        },
        {
          '_id': 'fld_2',
          '_type': 'request_group',
          'parentId': 'fld_1',
          'name': 'Admin',
        },
        {
          '_id': 'req_1',
          '_type': 'request',
          'parentId': 'fld_1',
          'name': 'List users',
          'method': 'GET',
          'url': 'https://{{ _.host }}/users',
          'headers': [
            {'name': 'Accept', 'value': 'application/json'},
          ],
          'parameters': [
            {'name': 'page', 'value': '1'},
          ],
        },
        {
          '_id': 'req_2',
          '_type': 'request',
          'parentId': 'fld_2',
          'name': 'Delete user',
          'method': 'DELETE',
          'url': 'https://{{ _.host }}/users/1',
        },
        {
          '_id': 'env_1',
          '_type': 'environment',
          'parentId': 'wrk_1',
          'name': 'dev',
          'data': {'host': 'api.test', 'token': 'abc'},
        },
      ],
    };

    test('maps workspaces, nested groups, requests and environments', () {
      final result = importInsomnia(export);

      expect(result.groups, hasLength(1));
      expect(result.groups.single.name, 'Demo');
      expect(result.folders, hasLength(2));
      expect(result.collections, hasLength(2));
      expect(result.environments, hasLength(1));
      expect(result.environments.single.vars.map((kv) => '${kv.k}=${kv.v}'),
          containsAll(['host=api.test', 'token=abc']));

      final list = result.collections.firstWhere((entry) => entry.name == 'List users');
      expect(list.request!.url, 'https://{{host}}/users');
      expect(list.request!.headers.single.k, 'Accept');
      expect(list.request!.params.single.v, '1');
      expect(list.folderId, isNotEmpty);
    });

    test('exports a workspace that can be imported back', () {
      final result = importInsomnia(export);
      final encoded = toInsomnia(
        groups: result.groups,
        folders: result.folders,
        collections: result.collections,
        environments: result.environments,
      );
      final roundTrip = importInsomnia(encoded);

      expect(roundTrip.collections, hasLength(2));
      expect(roundTrip.groups.single.name, 'Astra');
      expect(roundTrip.environments.single.vars.first.v, 'api.test');
    });
  });

  group('HTTP file import', () {
    test('parses variables, named requests, headers and bodies', () {
      final result = importHttpFile(
        '''
@base = https://api.test
# @name list
GET {{base}}/users
Accept: application/json

###
POST {{base}}/users
Content-Type: application/json

{"name":"astra"}
''',
        'demo.http',
      );

      expect(result.groups.single.name, 'demo');
      expect(result.groups.single.variables.map((kv) => '${kv.k}=${kv.v}'),
          contains('base=https://api.test'));
      expect(result.collections, hasLength(2));

      final list = result.collections.first;
      expect(list.name, 'list');
      expect(list.request!.method, 'GET');
      expect(list.request!.url, '{{base}}/users');
      expect(list.request!.headers.single.k, 'Accept');

      final create = result.collections.last;
      expect(create.request!.method, 'POST');
      expect(create.request!.bodyMode, 'json');
      expect(create.request!.body, '{"name":"astra"}');
    });
  });

  group('Runner reports', () {
    final steps = [
      RunStepResult(
        entryId: 'a',
        name: 'List users',
        method: 'GET',
        url: 'https://api.test/users',
        status: 200,
        ms: 12,
        iteration: 1,
        failures: const [],
        error: null,
        body: '{}',
      ),
      RunStepResult(
        entryId: 'b',
        name: 'Create, user',
        method: 'POST',
        url: 'https://api.test/users',
        status: 500,
        ms: 30,
        iteration: 1,
        failures: const ['status expected 201'],
        error: null,
        body: '{}',
      ),
    ];

    test('CSV escapes commas and quotes', () {
      final csv = runnerReportCsv(
        collection: 'Demo',
        startedAt: DateTime.utc(2026, 1, 1),
        steps: steps,
      );
      expect(csv.split('\n').first, contains('iteration,request,method'));
      expect(csv, contains('"Create, user"'));
      expect(csv, contains('status expected 201'));
    });

    test('JUnit marks failed requests', () {
      final xml = runnerReportJunit(
        collection: 'Demo',
        startedAt: DateTime.utc(2026, 1, 1),
        steps: steps,
      );
      expect(xml, contains('tests="2" failures="1"'));
      expect(xml, contains('<failure message="status expected 201">'));
    });
  });
}

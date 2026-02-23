import 'dart:collection';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/tools/bigtable/query_tool.dart' as bigtable_query;
import 'package:test/test.dart';

class _FakeBigtableTable implements BigtableTableAdmin {
  _FakeBigtableTable({required this.tableId, Map<String, Object?>? families})
    : _families = families ?? <String, Object?>{};

  @override
  final String tableId;

  final Map<String, Object?> _families;

  @override
  Map<String, Object?> listColumnFamilies() {
    return Map<String, Object?>.from(_families);
  }
}

class _FakeBigtableInstance implements BigtableAdminInstance {
  _FakeBigtableInstance({
    required this.instanceId,
    required this.displayName,
    required this.state,
    required this.type,
    required this.labels,
    List<BigtableTableAdmin>? tables,
  }) : _tables = tables ?? <BigtableTableAdmin>[];

  @override
  final String instanceId;

  @override
  final String displayName;

  @override
  final Object? state;

  @override
  final Object? type;

  @override
  final Map<String, Object?> labels;

  final List<BigtableTableAdmin> _tables;
  int reloadCount = 0;

  @override
  Iterable<BigtableTableAdmin> listTables() {
    return _tables;
  }

  @override
  void reload() {
    reloadCount += 1;
  }

  @override
  BigtableTableAdmin table(String tableId) {
    return _tables.firstWhere(
      (BigtableTableAdmin table) => table.tableId == tableId,
      orElse: () => throw StateError('Unknown table: $tableId'),
    );
  }
}

class _FakeBigtableAdminClient implements BigtableAdminClient {
  _FakeBigtableAdminClient({required this.instances});

  final Map<String, _FakeBigtableInstance> instances;
  final List<String> failedLocations = const <String>[];

  @override
  BigtableInstanceListResult listInstances() {
    return BigtableInstanceListResult(
      instances: instances.values
          .map(
            (_FakeBigtableInstance instance) =>
                BigtableInstanceSummary(instanceId: instance.instanceId),
          )
          .toList(growable: false),
      failedLocations: failedLocations,
    );
  }

  @override
  BigtableAdminInstance instance(String instanceId) {
    final _FakeBigtableInstance? instance = instances[instanceId];
    if (instance == null) {
      throw StateError('Unknown instance: $instanceId');
    }
    return instance;
  }
}

class _FakeBigtableRow implements BigtableQueryRow {
  _FakeBigtableRow(this.fields);

  @override
  final Map<String, Object?> fields;
}

class _FakeBigtableQueryIterator extends IterableBase<BigtableQueryRow>
    implements BigtableQueryIterator {
  _FakeBigtableQueryIterator(this.rows);

  final List<BigtableQueryRow> rows;
  int closeCount = 0;

  @override
  void close() {
    closeCount += 1;
  }

  @override
  Iterator<BigtableQueryRow> get iterator => rows.iterator;
}

class _FakeBigtableDataClient implements BigtableDataClient {
  _FakeBigtableDataClient({required this.iterator});

  final _FakeBigtableQueryIterator iterator;
  final List<Map<String, String>> calls = <Map<String, String>>[];

  @override
  BigtableQueryIterator executeQuery({
    required String query,
    required String instanceId,
  }) {
    calls.add(<String, String>{'query': query, 'instance_id': instanceId});
    return iterator;
  }
}

Context _newToolContext({Map<String, Object?>? state}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_bigtable',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_bigtable',
      appName: 'app',
      userId: 'u1',
      state: state ?? <String, Object?>{},
    ),
  );
  return Context(invocationContext);
}

void main() {
  tearDown(resetBigtableClientFactories);

  group('bigtable settings parity', () {
    test('defaults and strict field validation', () {
      final BigtableToolSettings defaults = BigtableToolSettings();
      expect(defaults.maxQueryResultRows, 50);

      final BigtableToolSettings parsed = BigtableToolSettings.fromJson(
        <String, Object?>{'max_query_result_rows': 7},
      );
      expect(parsed.maxQueryResultRows, 7);

      expect(
        () => BigtableToolSettings.fromJson(<String, Object?>{
          'unexpected': true,
        }),
        throwsArgumentError,
      );
      expect(
        () => BigtableToolSettings.fromJson(<String, Object?>{
          'max_query_result_rows': 0,
        }),
        throwsArgumentError,
      );
    });
  });

  group('bigtable metadata parity', () {
    test('lists instances/tables and gets metadata info', () async {
      final _FakeBigtableInstance instance = _FakeBigtableInstance(
        instanceId: 'inst1',
        displayName: 'Instance 1',
        state: 'READY',
        type: 'PRODUCTION',
        labels: <String, Object?>{'env': 'dev'},
        tables: <BigtableTableAdmin>[
          _FakeBigtableTable(
            tableId: 'users',
            families: <String, Object?>{'cf1': true},
          ),
          _FakeBigtableTable(tableId: 'orders'),
        ],
      );
      final _FakeBigtableAdminClient adminClient = _FakeBigtableAdminClient(
        instances: <String, _FakeBigtableInstance>{'inst1': instance},
      );

      setBigtableClientFactories(
        adminClientFactory:
            ({
              required String project,
              required Object credentials,
              required String userAgent,
            }) {
              expect(project, 'project1');
              expect(userAgent, contains('adk-bigtable-tool'));
              return adminClient;
            },
      );

      final Map<String, Object?> instances = await listInstances(
        projectId: 'project1',
        credentials: Object(),
      );
      expect(instances['status'], 'SUCCESS');
      expect(instances['results'], <String>['inst1']);

      final Map<String, Object?> instanceInfo = await getInstanceInfo(
        projectId: 'project1',
        instanceId: 'inst1',
        credentials: Object(),
      );
      expect(instanceInfo['status'], 'SUCCESS');
      expect((instanceInfo['results'] as Map)['display_name'], 'Instance 1');
      expect(instance.reloadCount, 1);

      final Map<String, Object?> tables = await listTables(
        projectId: 'project1',
        instanceId: 'inst1',
        credentials: Object(),
      );
      expect(tables['status'], 'SUCCESS');
      expect(tables['results'], <String>['users', 'orders']);

      final Map<String, Object?> tableInfo = await getTableInfo(
        projectId: 'project1',
        instanceId: 'inst1',
        tableId: 'users',
        credentials: Object(),
      );
      expect(tableInfo['status'], 'SUCCESS');
      expect((tableInfo['results'] as Map)['column_families'], <String>['cf1']);
    });

    test('returns ERROR payload when admin client fails', () async {
      setBigtableClientFactories(
        adminClientFactory:
            ({
              required String project,
              required Object credentials,
              required String userAgent,
            }) {
              throw StateError('admin unavailable');
            },
      );

      final Map<String, Object?> result = await listInstances(
        projectId: 'project1',
        credentials: Object(),
      );
      expect(result['status'], 'ERROR');
      expect('${result['error_details']}', contains('admin unavailable'));
    });
  });

  group('bigtable query parity', () {
    test('execute_sql returns truncated rows and closes iterator', () async {
      final _FakeBigtableQueryIterator iterator = _FakeBigtableQueryIterator(
        <BigtableQueryRow>[
          _FakeBigtableRow(<String, Object?>{'id': 1, 'name': 'Alice'}),
          _FakeBigtableRow(<String, Object?>{'id': 2, 'blob': Object()}),
        ],
      );
      final _FakeBigtableDataClient dataClient = _FakeBigtableDataClient(
        iterator: iterator,
      );

      setBigtableClientFactories(
        dataClientFactory:
            ({
              required String project,
              required Object credentials,
              required String userAgent,
            }) {
              expect(userAgent, contains('google-adk/'));
              return dataClient;
            },
      );

      final Map<String, Object?> result = await bigtable_query.executeSql(
        projectId: 'project1',
        instanceId: 'inst1',
        query: 'SELECT * FROM users',
        credentials: Object(),
        settings: BigtableToolSettings(maxQueryResultRows: 1),
        toolContext: _newToolContext(),
      );

      expect(result['status'], 'SUCCESS');
      expect((result['rows'] as List).length, 1);
      expect(result['result_is_likely_truncated'], isTrue);
      expect(iterator.closeCount, 1);
      expect(dataClient.calls.single['instance_id'], 'inst1');
    });

    test('execute_sql returns ERROR payload when data client throws', () async {
      setBigtableClientFactories(
        dataClientFactory:
            ({
              required String project,
              required Object credentials,
              required String userAgent,
            }) {
              throw StateError('query failed');
            },
      );

      final Map<String, Object?> result = await bigtable_query.executeSql(
        projectId: 'project1',
        instanceId: 'inst1',
        query: 'SELECT 1',
        credentials: Object(),
        settings: BigtableToolSettings(),
        toolContext: _newToolContext(),
      );

      expect(result['status'], 'ERROR');
      expect('${result['error_details']}', contains('query failed'));
    });
  });

  group('bigtable toolset parity', () {
    test('returns all tools, supports filtering and prefixing', () async {
      final BigtableToolset all = BigtableToolset();
      final List<BaseTool> tools = await all.getTools();
      expect(tools.map((BaseTool tool) => tool.name).toSet(), <String>{
        'list_instances',
        'get_instance_info',
        'list_tables',
        'get_table_info',
        'execute_sql',
      });

      final BigtableToolset filtered = BigtableToolset(
        toolFilter: <String>['list_tables'],
      );
      final List<BaseTool> filteredTools = await filtered.getTools();
      expect(filteredTools, hasLength(1));
      expect(filteredTools.single.name, 'list_tables');

      final List<BaseTool> prefixed = await all.getToolsWithPrefix();
      expect(
        prefixed.any((BaseTool tool) => tool.name == 'bigtable_execute_sql'),
        isTrue,
      );
    });

    test(
      'GoogleTool bridge injects credentials/settings into execute_sql',
      () async {
        final _FakeBigtableQueryIterator iterator = _FakeBigtableQueryIterator(
          <BigtableQueryRow>[
            _FakeBigtableRow(<String, Object?>{'id': 1}),
          ],
        );
        final _FakeBigtableDataClient dataClient = _FakeBigtableDataClient(
          iterator: iterator,
        );

        Object? capturedCredentials;
        setBigtableClientFactories(
          dataClientFactory:
              ({
                required String project,
                required Object credentials,
                required String userAgent,
              }) {
                capturedCredentials = credentials;
                return dataClient;
              },
        );

        final BigtableToolset toolset = BigtableToolset(
          credentialsConfig: BigtableCredentialsConfig(
            externalAccessTokenKey: 'bigtable_token',
          ),
          bigtableToolSettings: BigtableToolSettings(maxQueryResultRows: 5),
        );

        final BaseTool queryTool = (await toolset.getTools()).singleWhere(
          (BaseTool tool) => tool.name == 'execute_sql',
        );
        final Object? response = await queryTool.run(
          args: <String, dynamic>{
            'projectId': 'project1',
            'instanceId': 'inst1',
            'query': 'SELECT * FROM users',
          },
          toolContext: _newToolContext(
            state: <String, Object?>{'bigtable_token': 'token-123'},
          ),
        );

        expect(response, isA<Map<String, Object?>>());
        final Map<String, Object?> payload = response! as Map<String, Object?>;
        expect(payload['status'], 'SUCCESS');
        expect(capturedCredentials, isA<GoogleOAuthCredential>());
      },
    );
  });
}

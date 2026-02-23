import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeSpannerClient implements SpannerClient {
  _FakeSpannerClient({required this.instances, this.userAgent = ''});

  final Map<String, _FakeSpannerInstance> instances;

  @override
  String userAgent;

  @override
  SpannerInstance instance(String instanceId) {
    final _FakeSpannerInstance? instance = instances[instanceId];
    if (instance == null) {
      throw StateError('Unknown instance: $instanceId');
    }
    return instance;
  }
}

class _FakeSpannerInstance implements SpannerInstance {
  _FakeSpannerInstance({required this.databases});

  final Map<String, _FakeSpannerDatabase> databases;

  @override
  bool exists() => true;

  @override
  SpannerDatabase database(String databaseId) {
    final _FakeSpannerDatabase? database = databases[databaseId];
    if (database == null) {
      throw StateError('Unknown database: $databaseId');
    }
    return database;
  }
}

class _SqlInvocation {
  _SqlInvocation({
    required this.sql,
    required this.params,
    required this.paramTypes,
    required this.multiUse,
  });

  final String sql;
  final Map<String, Object?>? params;
  final Map<String, Object?>? paramTypes;
  final bool multiUse;
}

class _FakeSpannerDatabase implements SpannerDatabase {
  _FakeSpannerDatabase({
    required this.databaseDialect,
    List<SpannerTable>? tables,
  }) : _tables = tables ?? <SpannerTable>[];

  @override
  final SpannerDatabaseDialect databaseDialect;

  final List<SpannerTable> _tables;
  final List<_SqlInvocation> sqlInvocations = <_SqlInvocation>[];
  final List<List<String>> ddlStatements = <List<String>>[];
  final List<Map<String, Object?>> batchInsertCalls = <Map<String, Object?>>[];

  int reloadCount = 0;
  String? lastListedSchema;

  SpannerResultSet Function({
    required String sql,
    required Map<String, Object?>? params,
    required Map<String, Object?>? paramTypes,
  })?
  onExecuteSql;

  @override
  bool exists() => true;

  @override
  Iterable<SpannerTable> listTables({String schema = '_default'}) {
    lastListedSchema = schema;
    return _tables;
  }

  @override
  SpannerSnapshot snapshot({bool multiUse = false}) {
    return _FakeSpannerSnapshot(database: this, multiUse: multiUse);
  }

  @override
  void reload() {
    reloadCount += 1;
  }

  @override
  SpannerUpdateDdlOperation updateDdl(List<String> statements) {
    ddlStatements.add(List<String>.from(statements));
    return _FakeUpdateDdlOperation();
  }

  @override
  SpannerBatch batch() {
    return _FakeSpannerBatch(batchInsertCalls);
  }
}

class _FakeSpannerSnapshot implements SpannerSnapshot {
  _FakeSpannerSnapshot({required this.database, required this.multiUse});

  final _FakeSpannerDatabase database;
  final bool multiUse;

  @override
  SpannerResultSet executeSql({
    required String sql,
    Map<String, Object?>? params,
    Map<String, Object?>? paramTypes,
  }) {
    database.sqlInvocations.add(
      _SqlInvocation(
        sql: sql,
        params: params == null ? null : Map<String, Object?>.from(params),
        paramTypes: paramTypes == null
            ? null
            : Map<String, Object?>.from(paramTypes),
        multiUse: multiUse,
      ),
    );

    if (database.onExecuteSql != null) {
      return database.onExecuteSql!(
        sql: sql,
        params: params,
        paramTypes: paramTypes,
      );
    }

    return _FakeSpannerResultSet(rowsData: <Object?>[]);
  }
}

class _FakeSpannerResultSet implements SpannerResultSet {
  _FakeSpannerResultSet({required this.rowsData, this.dictRows});

  final List<Object?> rowsData;
  final List<Map<String, Object?>>? dictRows;

  @override
  Iterable<Object?> get rows => rowsData;

  @override
  Object? one() {
    return rowsData.isEmpty ? null : rowsData.first;
  }

  @override
  List<Map<String, Object?>> toDictList() {
    return dictRows ??
        rowsData
            .map((Object? row) {
              if (row is Map<String, Object?>) {
                return Map<String, Object?>.from(row);
              }
              if (row is Map) {
                return row.map(
                  (Object? key, Object? value) => MapEntry('$key', value),
                );
              }
              return <String, Object?>{'': row};
            })
            .toList(growable: false);
  }
}

class _FakeUpdateDdlOperation implements SpannerUpdateDdlOperation {
  bool called = false;

  @override
  void result() {
    called = true;
  }
}

class _FakeSpannerBatch implements SpannerBatch {
  _FakeSpannerBatch(this.calls);

  final List<Map<String, Object?>> calls;

  @override
  void insertOrUpdate({
    required String table,
    required List<String> columns,
    required List<List<Object?>> values,
  }) {
    calls.add(<String, Object?>{
      'table': table,
      'columns': List<String>.from(columns),
      'values': values
          .map((List<Object?> row) => List<Object?>.from(row))
          .toList(),
    });
  }
}

Context _newToolContext({Map<String, Object?>? state}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_spanner',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_spanner',
      appName: 'app',
      userId: 'u1',
      state: state ?? <String, Object?>{},
    ),
  );
  return Context(invocationContext);
}

void main() {
  tearDown(() {
    resetSpannerClientFactory();
    resetSpannerEmbedders();
  });

  group('spanner settings parity', () {
    test('defaults selected columns and validates vector settings', () {
      final SpannerVectorStoreSettings settings = SpannerVectorStoreSettings(
        projectId: 'p',
        instanceId: 'i',
        databaseId: 'd',
        tableName: 't',
        contentColumn: 'content',
        embeddingColumn: 'embedding',
        vectorLength: 3,
        vertexAiEmbeddingModelName: 'text-embedding-005',
      );

      expect(settings.selectedColumns, <String>['content']);

      expect(
        () => SpannerVectorStoreSettings(
          projectId: 'p',
          instanceId: 'i',
          databaseId: 'd',
          tableName: 't',
          contentColumn: 'content',
          embeddingColumn: 'embedding',
          vectorLength: 0,
          vertexAiEmbeddingModelName: 'text-embedding-005',
        ),
        throwsArgumentError,
      );

      expect(
        () => SpannerVectorStoreSettings(
          projectId: 'p',
          instanceId: 'i',
          databaseId: 'd',
          tableName: 't',
          contentColumn: 'content',
          embeddingColumn: 'embedding',
          vectorLength: 4,
          vertexAiEmbeddingModelName: 'text-embedding-005',
          primaryKeyColumns: <String>['id'],
        ),
        throwsArgumentError,
      );
    });

    test('parses tool settings from json and rejects unknown fields', () {
      final SpannerToolSettings settings = SpannerToolSettings.fromJson(
        <String, Object?>{
          'capabilities': <String>['data_read'],
          'max_executed_query_result_rows': 7,
          'query_result_mode': 'dict_list',
        },
      );
      expect(settings.maxExecutedQueryResultRows, 7);
      expect(settings.queryResultMode, QueryResultMode.dictList);
      expect(settings.capabilities, <Capabilities>[Capabilities.dataRead]);

      expect(
        () => SpannerToolSettings.fromJson(<String, Object?>{
          'unknown_field': true,
        }),
        throwsArgumentError,
      );
    });
  });

  group('spanner metadata/query parity', () {
    test('metadata tools return success payloads and schema details', () async {
      final _FakeSpannerDatabase database = _FakeSpannerDatabase(
        databaseDialect: SpannerDatabaseDialect.googleStandardSql,
        tables: const <SpannerTable>[
          SpannerTable(tableId: 'orders'),
          SpannerTable(tableId: 'customers'),
        ],
      );
      database.onExecuteSql =
          ({
            required String sql,
            required Map<String, Object?>? params,
            required Map<String, Object?>? paramTypes,
          }) {
            if (sql.contains('INFORMATION_SCHEMA.COLUMNS')) {
              return _FakeSpannerResultSet(
                rowsData: <Object?>[
                  <Object?>[
                    'id',
                    '',
                    'INT64',
                    1,
                    null,
                    'NO',
                    'NEVER',
                    null,
                    null,
                  ],
                ],
              );
            }
            if (sql.contains('INFORMATION_SCHEMA.KEY_COLUMN_USAGE')) {
              return _FakeSpannerResultSet(
                rowsData: <Object?>[
                  <Object?>['id', 'PK_Orders', 1, null],
                ],
              );
            }
            if (sql.contains('INFORMATION_SCHEMA.TABLES')) {
              return _FakeSpannerResultSet(
                rowsData: <Object?>[
                  <Object?>[
                    '',
                    'orders',
                    'BASE TABLE',
                    null,
                    null,
                    'COMMITTED',
                    null,
                    null,
                  ],
                ],
              );
            }
            if (sql.contains('INFORMATION_SCHEMA.INDEX_COLUMNS')) {
              return _FakeSpannerResultSet(
                rowsData: <Object?>[
                  <Object?>['PRIMARY_KEY', '', 'id', 1, 'NO', 'INT64'],
                ],
              );
            }
            if (sql.contains('INFORMATION_SCHEMA.INDEXES')) {
              return _FakeSpannerResultSet(
                rowsData: <Object?>[
                  <Object?>[
                    'PRIMARY_KEY',
                    '',
                    'PRIMARY_KEY',
                    '',
                    true,
                    false,
                    null,
                  ],
                ],
              );
            }
            if (sql.contains('INFORMATION_SCHEMA.SCHEMATA')) {
              return _FakeSpannerResultSet(
                rowsData: <Object?>[
                  <Object?>['sales'],
                ],
              );
            }
            return _FakeSpannerResultSet(rowsData: <Object?>[]);
          };

      final _FakeSpannerClient client = _FakeSpannerClient(
        instances: <String, _FakeSpannerInstance>{
          'inst1': _FakeSpannerInstance(
            databases: <String, _FakeSpannerDatabase>{'db1': database},
          ),
        },
      );
      setSpannerClientFactory(
        ({required String project, required Object credentials}) => client,
      );

      final Map<String, Object?> tables = await listTableNames(
        projectId: 'project1',
        instanceId: 'inst1',
        databaseId: 'db1',
        credentials: Object(),
      );
      expect(tables['status'], 'SUCCESS');
      expect(tables['results'], <String>['orders', 'customers']);
      expect(database.lastListedSchema, '_default');

      final Map<String, Object?> schema = await getTableSchema(
        projectId: 'project1',
        instanceId: 'inst1',
        databaseId: 'db1',
        tableName: 'orders',
        credentials: Object(),
      );
      expect(schema['status'], 'SUCCESS');
      final Map<String, Object?> schemaResults = Map<String, Object?>.from(
        schema['results']! as Map,
      );
      final Map<String, Object?> columns = Map<String, Object?>.from(
        schemaResults['schema']! as Map,
      );
      final Map<String, Object?> id = Map<String, Object?>.from(
        columns['id']! as Map,
      );
      expect(id['SPANNER_TYPE'], 'INT64');
      expect(id.containsKey('KEY_COLUMN_USAGE'), isTrue);

      final Map<String, Object?> indexes = await listTableIndexes(
        projectId: 'project1',
        instanceId: 'inst1',
        databaseId: 'db1',
        tableId: 'orders',
        credentials: Object(),
      );
      expect(indexes['status'], 'SUCCESS');
      expect((indexes['results'] as List).length, 1);

      final Map<String, Object?> indexColumns = await listTableIndexColumns(
        projectId: 'project1',
        instanceId: 'inst1',
        databaseId: 'db1',
        tableId: 'orders',
        credentials: Object(),
      );
      expect(indexColumns['status'], 'SUCCESS');

      final Map<String, Object?> schemas = await listNamedSchemas(
        projectId: 'project1',
        instanceId: 'inst1',
        databaseId: 'db1',
        credentials: Object(),
      );
      expect(schemas['status'], 'SUCCESS');
      expect(schemas['results'], <String>['sales']);
    });

    test('execute_sql handles truncation and dict_list mode', () async {
      final _FakeSpannerDatabase database = _FakeSpannerDatabase(
        databaseDialect: SpannerDatabaseDialect.googleStandardSql,
      );
      database.onExecuteSql =
          ({
            required String sql,
            required Map<String, Object?>? params,
            required Map<String, Object?>? paramTypes,
          }) {
            return _FakeSpannerResultSet(
              rowsData: <Object?>[
                <Object?>[1],
                <Object?>[2],
                <Object?>[3],
              ],
              dictRows: <Map<String, Object?>>[
                <String, Object?>{'count': 1},
                <String, Object?>{'count': 2},
              ],
            );
          };

      final _FakeSpannerClient client = _FakeSpannerClient(
        instances: <String, _FakeSpannerInstance>{
          'inst': _FakeSpannerInstance(
            databases: <String, _FakeSpannerDatabase>{'db': database},
          ),
        },
      );
      setSpannerClientFactory(
        ({required String project, required Object credentials}) => client,
      );

      final Map<String, Object?> defaultResult = await executeSql(
        projectId: 'p',
        instanceId: 'inst',
        databaseId: 'db',
        query: 'SELECT 1',
        credentials: Object(),
        settings: SpannerToolSettings(maxExecutedQueryResultRows: 2),
        toolContext: _newToolContext(),
      );
      expect(defaultResult['status'], 'SUCCESS');
      expect((defaultResult['rows'] as List).length, 2);
      expect(defaultResult['result_is_likely_truncated'], isTrue);

      final Map<String, Object?> dictResult = await executeSql(
        projectId: 'p',
        instanceId: 'inst',
        databaseId: 'db',
        query: 'SELECT 1',
        credentials: Object(),
        settings: SpannerToolSettings(
          maxExecutedQueryResultRows: 5,
          queryResultMode: QueryResultMode.dictList,
        ),
        toolContext: _newToolContext(),
      );
      expect((dictResult['rows'] as List).first, <String, Object?>{'count': 1});
    });
  });

  group('spanner search parity', () {
    test('similarity_search validates options and returns rows', () async {
      final _FakeSpannerDatabase database = _FakeSpannerDatabase(
        databaseDialect: SpannerDatabaseDialect.googleStandardSql,
      );
      database.onExecuteSql =
          ({
            required String sql,
            required Map<String, Object?>? params,
            required Map<String, Object?>? paramTypes,
          }) {
            expect(sql, contains('COSINE_DISTANCE'));
            return _FakeSpannerResultSet(
              rowsData: <Object?>[
                <Object?>['doc1', 0.12],
                <Object?>['doc2', 0.24],
              ],
            );
          };
      final _FakeSpannerClient client = _FakeSpannerClient(
        instances: <String, _FakeSpannerInstance>{
          'inst': _FakeSpannerInstance(
            databases: <String, _FakeSpannerDatabase>{'db': database},
          ),
        },
      );
      setSpannerClientFactory(
        ({required String project, required Object credentials}) => client,
      );
      setSpannerEmbedders(
        embedder:
            ({
              required String vertexAiEmbeddingModelName,
              required List<String> contents,
              int? outputDimensionality,
              Object? genAiClient,
            }) {
              return <List<double>>[
                <double>[0.1, 0.2],
              ];
            },
      );

      final Map<String, Object?> result = await similaritySearch(
        projectId: 'p',
        instanceId: 'inst',
        databaseId: 'db',
        tableName: 'docs',
        query: 'find me docs',
        embeddingColumnToSearch: 'embedding',
        columns: <String>['content'],
        embeddingOptions: <String, Object?>{
          'vertex_ai_embedding_model_name': 'text-embedding-005',
        },
        credentials: Object(),
      );

      expect(result['status'], 'SUCCESS');
      expect((result['rows'] as List).length, 2);

      final Map<String, Object?> invalid = await similaritySearch(
        projectId: 'p',
        instanceId: 'inst',
        databaseId: 'db',
        tableName: 'docs',
        query: 'find',
        embeddingColumnToSearch: 'embedding',
        columns: <String>['content'],
        embeddingOptions: <String, Object?>{},
        credentials: Object(),
      );
      expect(invalid['status'], 'ERROR');
      expect(
        '${invalid['error_details']}',
        contains('Exactly one embedding model'),
      );
    });

    test(
      'vector_store_similarity_search uses settings-derived options',
      () async {
        final _FakeSpannerDatabase database = _FakeSpannerDatabase(
          databaseDialect: SpannerDatabaseDialect.googleStandardSql,
        );
        database.onExecuteSql =
            ({
              required String sql,
              required Map<String, Object?>? params,
              required Map<String, Object?>? paramTypes,
            }) {
              expect(sql, contains('LIMIT 3'));
              return _FakeSpannerResultSet(
                rowsData: <Object?>[
                  <Object?>['doc1', 0.09],
                ],
              );
            };
        final _FakeSpannerClient client = _FakeSpannerClient(
          instances: <String, _FakeSpannerInstance>{
            'inst': _FakeSpannerInstance(
              databases: <String, _FakeSpannerDatabase>{'db': database},
            ),
          },
        );
        setSpannerClientFactory(
          ({required String project, required Object credentials}) => client,
        );
        setSpannerEmbedders(
          embedder:
              ({
                required String vertexAiEmbeddingModelName,
                required List<String> contents,
                int? outputDimensionality,
                Object? genAiClient,
              }) {
                return <List<double>>[
                  <double>[0.1, 0.2],
                ];
              },
        );

        final SpannerToolSettings settings = SpannerToolSettings(
          vectorStoreSettings: SpannerVectorStoreSettings(
            projectId: 'p',
            instanceId: 'inst',
            databaseId: 'db',
            tableName: 'docs',
            contentColumn: 'content',
            embeddingColumn: 'embedding',
            vectorLength: 2,
            vertexAiEmbeddingModelName: 'text-embedding-005',
            topK: 3,
            selectedColumns: <String>['content'],
          ),
        );

        final Map<String, Object?> result = await vectorStoreSimilaritySearch(
          query: 'hello',
          credentials: Object(),
          settings: settings,
        );
        expect(result['status'], 'SUCCESS');
      },
    );
  });

  group('spanner vector store and toolset parity', () {
    test(
      'vector store builds ddl and inserts embedded content batches',
      () async {
        final _FakeSpannerDatabase database = _FakeSpannerDatabase(
          databaseDialect: SpannerDatabaseDialect.googleStandardSql,
        );
        final _FakeSpannerClient client = _FakeSpannerClient(
          userAgent: 'custom-agent',
          instances: <String, _FakeSpannerInstance>{
            'inst': _FakeSpannerInstance(
              databases: <String, _FakeSpannerDatabase>{'db': database},
            ),
          },
        );

        setSpannerEmbedders(
          embedder:
              ({
                required String vertexAiEmbeddingModelName,
                required List<String> contents,
                int? outputDimensionality,
                Object? genAiClient,
              }) {
                return contents
                    .map(
                      (String content) => <double>[content.length.toDouble()],
                    )
                    .toList(growable: false);
              },
        );

        final SpannerToolSettings settings = SpannerToolSettings(
          vectorStoreSettings: SpannerVectorStoreSettings(
            projectId: 'p',
            instanceId: 'inst',
            databaseId: 'db',
            tableName: 'docs',
            contentColumn: 'content',
            embeddingColumn: 'embedding',
            vectorLength: 1,
            vertexAiEmbeddingModelName: 'text-embedding-005',
            additionalColumnsToSetup: <TableColumn>[
              TableColumn(
                name: 'source',
                type: 'STRING(MAX)',
                isNullable: false,
              ),
            ],
            vectorSearchIndexSettings: VectorSearchIndexSettings(
              indexName: 'docs_idx',
              treeDepth: 2,
              numLeaves: 100,
            ),
          ),
        );

        final SpannerVectorStore store = SpannerVectorStore(
          settings: settings,
          spannerClient: client,
        );

        final String tableDdl = store.createVectorStoreTableDdl(
          SpannerDatabaseDialect.googleStandardSql,
        );
        expect(tableDdl, contains('CREATE TABLE IF NOT EXISTS docs'));
        expect(tableDdl, contains('ARRAY<FLOAT32>(vector_length=>1)'));

        final String indexDdl = store.createAnnVectorSearchIndexDdl(
          SpannerDatabaseDialect.googleStandardSql,
        );
        expect(
          indexDdl,
          contains('CREATE VECTOR INDEX IF NOT EXISTS docs_idx'),
        );

        await store.createVectorStore();
        await store.createVectorSearchIndex();
        expect(database.ddlStatements, hasLength(2));

        await store.addContents(
          contents: <String>['a', 'bb'],
          additionalColumnsValues: <Map<String, Object?>>[
            <String, Object?>{'source': 's1'},
            <String, Object?>{'source': 's2'},
          ],
          batchSize: 1,
        );
        expect(database.reloadCount, 1);
        expect(database.batchInsertCalls, hasLength(2));
        expect(database.batchInsertCalls.first['table'], 'docs');
      },
    );

    test(
      'toolset returns expected tools and GoogleTool bridge runs execute_sql',
      () async {
        final _FakeSpannerDatabase database = _FakeSpannerDatabase(
          databaseDialect: SpannerDatabaseDialect.googleStandardSql,
        );
        database.onExecuteSql =
            ({
              required String sql,
              required Map<String, Object?>? params,
              required Map<String, Object?>? paramTypes,
            }) {
              return _FakeSpannerResultSet(
                rowsData: <Object?>[
                  <Object?>[1],
                ],
              );
            };

        final _FakeSpannerClient client = _FakeSpannerClient(
          instances: <String, _FakeSpannerInstance>{
            'inst': _FakeSpannerInstance(
              databases: <String, _FakeSpannerDatabase>{'db': database},
            ),
          },
        );

        Object? capturedCredentials;
        setSpannerClientFactory(({
          required String project,
          required Object credentials,
        }) {
          capturedCredentials = credentials;
          return client;
        });

        final SpannerToolset toolset = SpannerToolset(
          credentialsConfig: SpannerCredentialsConfig(
            externalAccessTokenKey: 'spanner_token',
          ),
        );

        final List<BaseTool> tools = await toolset.getTools();
        expect(tools.map((BaseTool tool) => tool.name).toSet(), <String>{
          'list_table_names',
          'list_table_indexes',
          'list_table_index_columns',
          'list_named_schemas',
          'get_table_schema',
          'execute_sql',
          'similarity_search',
        });

        final BaseTool executeTool = tools.singleWhere(
          (BaseTool tool) => tool.name == 'execute_sql',
        );
        final Object? response = await executeTool.run(
          args: <String, dynamic>{
            'projectId': 'p',
            'instanceId': 'inst',
            'databaseId': 'db',
            'query': 'SELECT 1',
          },
          toolContext: _newToolContext(
            state: <String, Object?>{'spanner_token': 'token-value'},
          ),
        );

        expect(response, isA<Map<String, Object?>>());
        final Map<String, Object?> payload = response! as Map<String, Object?>;
        expect(payload['status'], 'SUCCESS');
        expect(capturedCredentials, isA<GoogleOAuthCredential>());

        final List<BaseTool> prefixed = await toolset.getToolsWithPrefix();
        expect(
          prefixed.any((BaseTool tool) => tool.name == 'spanner_execute_sql'),
          isTrue,
        );
      },
    );
  });
}

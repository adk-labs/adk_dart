import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/tools/bigquery/data_insights_tool.dart'
    as data_insights_tool;
import 'package:adk_dart/src/tools/bigquery/metadata_tool.dart'
    as bigquery_metadata;
import 'package:adk_dart/src/tools/bigquery/query_tool.dart' as query_tool;
import 'package:adk_dart/src/tools/bigquery/bigquery_toolset.dart'
    as bigquery_toolset;
import 'package:test/test.dart';

class _FakeDatasetListItem implements BigQueryDatasetListItem {
  _FakeDatasetListItem(this.datasetId);

  @override
  final String datasetId;
}

class _FakeTableListItem implements BigQueryTableListItem {
  _FakeTableListItem(this.tableId);

  @override
  final String tableId;
}

class _FakeResourceInfo implements BigQueryResourceInfo {
  _FakeResourceInfo(this.payload);

  final Map<String, Object?> payload;

  @override
  Map<String, Object?> toApiRepr() => Map<String, Object?>.from(payload);
}

class _FakeJobInfo implements BigQueryJobInfo {
  _FakeJobInfo(this.properties);

  @override
  final Map<String, Object?> properties;
}

class _FakeQueryJob implements BigQueryQueryJob {
  _FakeQueryJob({
    this.statementType,
    this.destination,
    this.sessionInfo,
    Map<String, Object?>? apiRepr,
  }) : _apiRepr = apiRepr ?? <String, Object?>{};

  @override
  final String? statementType;

  @override
  final BigQueryTableReference? destination;

  @override
  final BigQuerySessionInfo? sessionInfo;

  final Map<String, Object?> _apiRepr;

  @override
  Map<String, Object?> toApiRepr() => Map<String, Object?>.from(_apiRepr);
}

class _FakeBigQueryClient implements BigQueryClient {
  Iterable<BigQueryDatasetListItem> datasets = <BigQueryDatasetListItem>[];
  final Map<String, Iterable<BigQueryTableListItem>> tablesByDataset =
      <String, Iterable<BigQueryTableListItem>>{};
  final Map<String, Map<String, Object?>> datasetInfoById =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> tableInfoByKey =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> jobInfoById =
      <String, Map<String, Object?>>{};

  BigQueryQueryJob Function({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
  })?
  onQuery;

  Iterable<Map<String, Object?>> Function({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
    required int maxResults,
  })?
  onQueryAndWait;

  final List<Map<String, Object?>> queryCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> queryAndWaitCalls = <Map<String, Object?>>[];

  @override
  BigQueryResourceInfo getDataset(BigQueryDatasetReference reference) {
    final Map<String, Object?> payload =
        datasetInfoById[reference.datasetId] ?? <String, Object?>{};
    return _FakeResourceInfo(payload);
  }

  @override
  BigQueryJobInfo getJob(String jobId) {
    return _FakeJobInfo(jobInfoById[jobId] ?? <String, Object?>{});
  }

  @override
  BigQueryResourceInfo getTable(BigQueryTableReference reference) {
    final String key = '${reference.datasetId}.${reference.tableId}';
    return _FakeResourceInfo(tableInfoByKey[key] ?? <String, Object?>{});
  }

  @override
  Iterable<BigQueryDatasetListItem> listDatasets(String projectId) {
    return datasets;
  }

  @override
  Iterable<BigQueryTableListItem> listTables(
    BigQueryDatasetReference reference,
  ) {
    return tablesByDataset[reference.datasetId] ?? <BigQueryTableListItem>[];
  }

  @override
  BigQueryQueryJob query({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
  }) {
    queryCalls.add(<String, Object?>{
      'query': query,
      'project': project,
      'dry_run': jobConfig.dryRun,
      'create_session': jobConfig.createSession,
      'labels': jobConfig.labels,
      'connection_properties': jobConfig.connectionProperties
          .map(
            (BigQueryConnectionProperty property) => <String, String>{
              'key': property.key,
              'value': property.value,
            },
          )
          .toList(growable: false),
    });

    final BigQueryQueryJob Function({
      required String query,
      required String project,
      required BigQueryQueryJobConfig jobConfig,
    })?
    handler = onQuery;
    if (handler != null) {
      return handler(query: query, project: project, jobConfig: jobConfig);
    }

    return _FakeQueryJob(statementType: 'SELECT');
  }

  @override
  Iterable<Map<String, Object?>> queryAndWait({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
    required int maxResults,
  }) {
    queryAndWaitCalls.add(<String, Object?>{
      'query': query,
      'project': project,
      'max_results': maxResults,
      'labels': jobConfig.labels,
      'maximum_bytes_billed': jobConfig.maximumBytesBilled,
      'connection_properties': jobConfig.connectionProperties
          .map(
            (BigQueryConnectionProperty property) => <String, String>{
              'key': property.key,
              'value': property.value,
            },
          )
          .toList(growable: false),
    });

    final Iterable<Map<String, Object?>> Function({
      required String query,
      required String project,
      required BigQueryQueryJobConfig jobConfig,
      required int maxResults,
    })?
    handler = onQueryAndWait;
    if (handler != null) {
      return handler(
        query: query,
        project: project,
        jobConfig: jobConfig,
        maxResults: maxResults,
      );
    }

    return <Map<String, Object?>>[];
  }
}

Context _newToolContext({Map<String, Object?>? state}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_bigquery',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_bigquery',
      appName: 'app',
      userId: 'u1',
      state: state ?? <String, Object?>{},
    ),
  );
  return Context(invocationContext);
}

void main() {
  tearDown(() {
    resetBigQueryClientFactory();
    data_insights_tool.resetBigQueryInsightsStreamProvider();
  });

  group('bigquery config parity', () {
    test('defaults and strict field validation', () {
      final BigQueryToolConfig defaults = BigQueryToolConfig();
      expect(defaults.writeMode, WriteMode.blocked);
      expect(defaults.maxQueryResultRows, 50);

      final BigQueryToolConfig parsed = BigQueryToolConfig.fromJson(
        <String, Object?>{
          'write_mode': 'allowed',
          'max_query_result_rows': 10,
          'maximum_bytes_billed': 10485760,
          'application_name': 'agent_app',
          'compute_project_id': 'compute-p',
          'location': 'US',
          'job_labels': <String, String>{'env': 'dev'},
        },
      );
      expect(parsed.writeMode, WriteMode.allowed);
      expect(parsed.maxQueryResultRows, 10);
      expect(parsed.jobLabels, <String, String>{'env': 'dev'});

      expect(
        () => BigQueryToolConfig.fromJson(<String, Object?>{'unknown': true}),
        throwsArgumentError,
      );
      expect(
        () => BigQueryToolConfig.fromJson(<String, Object?>{
          'maximum_bytes_billed': 10,
        }),
        throwsArgumentError,
      );
      expect(
        () => BigQueryToolConfig.fromJson(<String, Object?>{
          'application_name': 'bad app',
        }),
        throwsArgumentError,
      );
      expect(
        () => BigQueryToolConfig.fromJson(<String, Object?>{
          'job_labels': <String, String>{'': 'invalid'},
        }),
        throwsArgumentError,
      );
    });
  });

  group('bigquery metadata parity', () {
    test('list/get dataset/table/job metadata', () async {
      final _FakeBigQueryClient client = _FakeBigQueryClient()
        ..datasets = <BigQueryDatasetListItem>[
          _FakeDatasetListItem('dataset_a'),
        ]
        ..tablesByDataset['dataset_a'] = <BigQueryTableListItem>[
          _FakeTableListItem('table_users'),
        ]
        ..datasetInfoById['dataset_a'] = <String, Object?>{
          'datasetReference': <String, Object?>{'datasetId': 'dataset_a'},
        }
        ..tableInfoByKey['dataset_a.table_users'] = <String, Object?>{
          'tableReference': <String, Object?>{'tableId': 'table_users'},
        }
        ..jobInfoById['job_1'] = <String, Object?>{
          'jobReference': <String, Object?>{'jobId': 'job_1'},
        };

      setBigQueryClientFactory(({
        required String? project,
        required Object credentials,
        String? location,
        required List<String> userAgent,
      }) {
        expect(project, 'project1');
        expect(userAgent.first, contains('adk-bigquery-tool'));
        return client;
      });

      final Object datasets = await bigquery_metadata.listDatasetIds(
        projectId: 'project1',
        credentials: Object(),
        settings: BigQueryToolConfig(),
      );
      expect(datasets, <String>['dataset_a']);

      final Map<String, Object?> datasetInfo = await bigquery_metadata
          .getDatasetInfo(
            projectId: 'project1',
            datasetId: 'dataset_a',
            credentials: Object(),
            settings: BigQueryToolConfig(),
          );
      expect(
        (datasetInfo['datasetReference'] as Map<String, Object?>)['datasetId'],
        'dataset_a',
      );

      final Object tables = await bigquery_metadata.listTableIds(
        projectId: 'project1',
        datasetId: 'dataset_a',
        credentials: Object(),
        settings: BigQueryToolConfig(),
      );
      expect(tables, <String>['table_users']);

      final Map<String, Object?> tableInfo = await bigquery_metadata
          .getTableInfo(
            projectId: 'project1',
            datasetId: 'dataset_a',
            tableId: 'table_users',
            credentials: Object(),
            settings: BigQueryToolConfig(),
          );
      expect(
        (tableInfo['tableReference'] as Map<String, Object?>)['tableId'],
        'table_users',
      );

      final Map<String, Object?> jobInfo = await bigquery_metadata.getJobInfo(
        projectId: 'project1',
        jobId: 'job_1',
        credentials: Object(),
        settings: BigQueryToolConfig(),
      );
      expect(
        (jobInfo['jobReference'] as Map<String, Object?>)['jobId'],
        'job_1',
      );
    });

    test('returns ERROR payload when client factory fails', () async {
      setBigQueryClientFactory(({
        required String? project,
        required Object credentials,
        String? location,
        required List<String> userAgent,
      }) {
        throw StateError('bigquery unavailable');
      });

      final Object result = await bigquery_metadata.listDatasetIds(
        projectId: 'project1',
        credentials: Object(),
        settings: BigQueryToolConfig(),
      );
      expect(result, isA<Map<String, Object?>>());
      final Map<String, Object?> payload = result as Map<String, Object?>;
      expect(payload['status'], 'ERROR');
      expect('${payload['error_details']}', contains('bigquery unavailable'));
    });
  });

  group('bigquery execute_sql parity', () {
    test('read-only mode blocks non-SELECT statements', () async {
      final _FakeBigQueryClient client = _FakeBigQueryClient()
        ..onQuery =
            ({
              required String query,
              required String project,
              required BigQueryQueryJobConfig jobConfig,
            }) {
              return _FakeQueryJob(statementType: 'INSERT');
            };

      setBigQueryClientFactory(
        ({
          required String? project,
          required Object credentials,
          String? location,
          required List<String> userAgent,
        }) => client,
      );

      final Map<String, Object?> result = await query_tool.executeSql(
        projectId: 'project1',
        query: 'INSERT INTO t VALUES (1)',
        credentials: Object(),
        settings: BigQueryToolConfig(writeMode: WriteMode.blocked),
        toolContext: _newToolContext(),
      );

      expect(result['status'], 'ERROR');
      expect(
        '${result['error_details']}',
        contains('Read-only mode only supports SELECT'),
      );
    });

    test('dry_run returns job api representation', () async {
      final _FakeBigQueryClient client = _FakeBigQueryClient()
        ..onQuery =
            ({
              required String query,
              required String project,
              required BigQueryQueryJobConfig jobConfig,
            }) {
              if (jobConfig.dryRun && !jobConfig.createSession) {
                return _FakeQueryJob(
                  statementType: 'SELECT',
                  apiRepr: <String, Object?>{
                    'configuration': <String, Object?>{'dryRun': true},
                  },
                );
              }
              return _FakeQueryJob(statementType: 'SELECT');
            };

      setBigQueryClientFactory(
        ({
          required String? project,
          required Object credentials,
          String? location,
          required List<String> userAgent,
        }) => client,
      );

      final Map<String, Object?> result = await query_tool.executeSql(
        projectId: 'project1',
        query: 'SELECT 1',
        credentials: Object(),
        settings: BigQueryToolConfig(),
        toolContext: _newToolContext(),
        dryRun: true,
      );

      expect(result['status'], 'SUCCESS');
      expect(
        (result['dry_run_info'] as Map<String, Object?>)['configuration'],
        <String, Object?>{'dryRun': true},
      );
    });

    test(
      'query execution truncates result and stringifies non-json values',
      () async {
        final _FakeBigQueryClient client = _FakeBigQueryClient()
          ..onQuery =
              ({
                required String query,
                required String project,
                required BigQueryQueryJobConfig jobConfig,
              }) {
                return _FakeQueryJob(statementType: 'SELECT');
              }
          ..onQueryAndWait =
              ({
                required String query,
                required String project,
                required BigQueryQueryJobConfig jobConfig,
                required int maxResults,
              }) {
                return <Map<String, Object?>>[
                  <String, Object?>{'id': 1, 'obj': Object()},
                  <String, Object?>{'id': 2, 'name': 'B'},
                ];
              };

        setBigQueryClientFactory(
          ({
            required String? project,
            required Object credentials,
            String? location,
            required List<String> userAgent,
          }) => client,
        );

        final Map<String, Object?> result = await query_tool.executeSql(
          projectId: 'project1',
          query: 'SELECT * FROM t',
          credentials: Object(),
          settings: BigQueryToolConfig(maxQueryResultRows: 2),
          toolContext: _newToolContext(),
        );

        expect(result['status'], 'SUCCESS');
        expect((result['rows'] as List).length, 2);
        expect(result['result_is_likely_truncated'], isTrue);
        expect('${((result['rows'] as List).first as Map)['obj']}', isNotEmpty);
      },
    );

    test('protected mode enforces writes only in session dataset', () async {
      final _FakeBigQueryClient client = _FakeBigQueryClient()
        ..onQuery =
            ({
              required String query,
              required String project,
              required BigQueryQueryJobConfig jobConfig,
            }) {
              if (jobConfig.createSession) {
                return _FakeQueryJob(
                  statementType: 'SELECT',
                  sessionInfo: const BigQuerySessionInfo(
                    sessionId: 'session_1',
                  ),
                  destination: BigQueryTableReference(
                    dataset: const BigQueryDatasetReference(
                      projectId: 'project1',
                      datasetId: '_anon',
                    ),
                    tableId: 'tmp',
                  ),
                );
              }
              return _FakeQueryJob(
                statementType: 'INSERT',
                destination: BigQueryTableReference(
                  dataset: const BigQueryDatasetReference(
                    projectId: 'project1',
                    datasetId: 'permanent_ds',
                  ),
                  tableId: 'target',
                ),
              );
            };

      setBigQueryClientFactory(
        ({
          required String? project,
          required Object credentials,
          String? location,
          required List<String> userAgent,
        }) => client,
      );

      final Context toolContext = _newToolContext();
      final Map<String, Object?> result = await query_tool.executeSql(
        projectId: 'project1',
        query: 'INSERT INTO target VALUES(1)',
        credentials: Object(),
        settings: BigQueryToolConfig(writeMode: WriteMode.protected),
        toolContext: toolContext,
      );

      expect(result['status'], 'ERROR');
      expect('${result['error_details']}', contains('Protected write mode'));
      expect(toolContext.state[query_tool.bigQuerySessionInfoKey], <String>[
        'session_1',
        '_anon',
      ]);
    });

    test('compute project guardrail is enforced', () async {
      final Map<String, Object?> result = await query_tool.executeSql(
        projectId: 'project1',
        query: 'SELECT 1',
        credentials: Object(),
        settings: BigQueryToolConfig(computeProjectId: 'project2'),
        toolContext: _newToolContext(),
      );

      expect(result['status'], 'ERROR');
      expect('${result['error_details']}', contains('restricted'));
    });
  });

  group('bigquery advanced query tools parity', () {
    test(
      'forecast validates id columns and builds AI.FORECAST query',
      () async {
        final _FakeBigQueryClient client = _FakeBigQueryClient()
          ..onQuery =
              ({
                required String query,
                required String project,
                required BigQueryQueryJobConfig jobConfig,
              }) {
                return _FakeQueryJob(statementType: 'SELECT');
              }
          ..onQueryAndWait =
              ({
                required String query,
                required String project,
                required BigQueryQueryJobConfig jobConfig,
                required int maxResults,
              }) {
                expect(query, contains('AI.FORECAST'));
                expect(query, contains("id_cols => ['series_id']"));
                return <Map<String, Object?>>[];
              };

        setBigQueryClientFactory(
          ({
            required String? project,
            required Object credentials,
            String? location,
            required List<String> userAgent,
          }) => client,
        );

        final Map<String, Object?> result = await query_tool.forecast(
          projectId: 'project1',
          historyData: 'dataset.table',
          timestampCol: 'ts',
          dataCol: 'value',
          idCols: <Object?>['series_id'],
          credentials: Object(),
          settings: BigQueryToolConfig(),
          toolContext: _newToolContext(),
        );

        expect(result['status'], 'SUCCESS');

        final Map<String, Object?> invalid = await query_tool.forecast(
          projectId: 'project1',
          historyData: 'dataset.table',
          timestampCol: 'ts',
          dataCol: 'value',
          idCols: <Object?>['series_id', 1],
          credentials: Object(),
          settings: BigQueryToolConfig(),
          toolContext: _newToolContext(),
        );
        expect(invalid['status'], 'ERROR');
      },
    );

    test(
      'analyze_contribution and detect_anomalies follow protected-session flow',
      () async {
        final _FakeBigQueryClient client = _FakeBigQueryClient()
          ..onQuery =
              ({
                required String query,
                required String project,
                required BigQueryQueryJobConfig jobConfig,
              }) {
                if (jobConfig.createSession) {
                  return _FakeQueryJob(
                    statementType: 'SELECT',
                    sessionInfo: const BigQuerySessionInfo(
                      sessionId: 'session_2',
                    ),
                    destination: BigQueryTableReference(
                      dataset: const BigQueryDatasetReference(
                        projectId: 'project1',
                        datasetId: '_anon2',
                      ),
                      tableId: 'tmp',
                    ),
                  );
                }

                if (query.contains('CREATE TEMP MODEL')) {
                  return _FakeQueryJob(
                    statementType: 'CREATE_MODEL',
                    destination: BigQueryTableReference(
                      dataset: const BigQueryDatasetReference(
                        projectId: 'project1',
                        datasetId: '_anon2',
                      ),
                      tableId: 'model_dest',
                    ),
                  );
                }

                return _FakeQueryJob(statementType: 'SELECT');
              }
          ..onQueryAndWait =
              ({
                required String query,
                required String project,
                required BigQueryQueryJobConfig jobConfig,
                required int maxResults,
              }) {
                if (query.contains('ML.GET_INSIGHTS')) {
                  return <Map<String, Object?>>[
                    <String, Object?>{'insight': 'top_dimension'},
                  ];
                }
                if (query.contains('ML.DETECT_ANOMALIES')) {
                  return <Map<String, Object?>>[
                    <String, Object?>{'is_anomaly': true},
                  ];
                }
                return <Map<String, Object?>>[];
              };

        setBigQueryClientFactory(
          ({
            required String? project,
            required Object credentials,
            String? location,
            required List<String> userAgent,
          }) => client,
        );

        final Context context = _newToolContext();
        final Map<String, Object?> contribution = await query_tool
            .analyzeContribution(
              projectId: 'project1',
              inputData: 'dataset.table',
              contributionMetric: 'SUM(value)',
              dimensionIdCols: <Object?>['store_id'],
              isTestCol: 'is_test',
              credentials: Object(),
              settings: BigQueryToolConfig(writeMode: WriteMode.allowed),
              toolContext: context,
            );
        expect(contribution['status'], 'SUCCESS');
        expect((contribution['rows'] as List).isNotEmpty, isTrue);

        final Map<String, Object?> detect = await query_tool.detectAnomalies(
          projectId: 'project1',
          historyData: 'dataset.table',
          timesSeriesTimestampCol: 'ts',
          timesSeriesDataCol: 'value',
          timesSeriesIdCols: <Object?>['series_id'],
          credentials: Object(),
          settings: BigQueryToolConfig(writeMode: WriteMode.allowed),
          toolContext: context,
        );
        expect(detect['status'], 'SUCCESS');
        expect((detect['rows'] as List).isNotEmpty, isTrue);

        final Map<String, Object?> invalidPruning = await query_tool
            .analyzeContribution(
              projectId: 'project1',
              inputData: 'dataset.table',
              contributionMetric: 'SUM(value)',
              dimensionIdCols: <Object?>['store_id'],
              isTestCol: 'is_test',
              pruningMethod: 'INVALID',
              credentials: Object(),
              settings: BigQueryToolConfig(writeMode: WriteMode.allowed),
              toolContext: context,
            );
        expect(invalidPruning['status'], 'ERROR');
      },
    );
  });

  group('bigquery data insights parity', () {
    test('requires access token and parses streamed responses', () async {
      final Map<String, Object?> missingToken = await data_insights_tool
          .askDataInsights(
            projectId: 'project1',
            userQueryWithContext: 'question',
            tableReferences: <Map<String, String>>[
              <String, String>{
                'projectId': 'project1',
                'datasetId': 'dataset',
                'tableId': 'table',
              },
            ],
            credentials: Object(),
            settings: BigQueryToolConfig(),
          );
      expect(missingToken['status'], 'ERROR');

      data_insights_tool.setBigQueryInsightsStreamProvider(({
        required Uri url,
        required Map<String, Object?> payload,
        required Map<String, String> headers,
      }) async {
        expect(url.toString(), contains('geminidataanalytics.googleapis.com'));
        expect(headers['Authorization'], 'Bearer token_123');

        return Stream<String>.fromIterable(<String>[
          '{"systemMessage":{"data":{"generatedSql":"SELECT 1"}}}',
          '{"systemMessage":{"data":{"result":{"schema":{"fields":[{"name":"id"}]},"data":[{"id":1},{"id":2}]}}}}',
          '{"systemMessage":{"text":{"parts":["Final answer"]}}}',
        ]);
      });

      final Map<String, Object?> result = await data_insights_tool
          .askDataInsights(
            projectId: 'project1',
            userQueryWithContext: 'question',
            tableReferences: <Map<String, String>>[
              <String, String>{
                'projectId': 'project1',
                'datasetId': 'dataset',
                'tableId': 'table',
              },
            ],
            credentials: GoogleOAuthCredential(accessToken: 'token_123'),
            settings: BigQueryToolConfig(maxQueryResultRows: 1),
          );

      expect(result['status'], 'SUCCESS');
      final List response = result['response'] as List;
      expect(response.first, <String, Object?>{'SQL Generated': 'SELECT 1'});
      expect(
        response.any((dynamic item) => '$item'.contains('Final answer')),
        isTrue,
      );
    });
  });

  group('bigquery toolset parity', () {
    test('returns tools and supports filtering', () async {
      final bigquery_toolset.BigQueryToolset all =
          bigquery_toolset.BigQueryToolset();
      final List<BaseTool> tools = await all.getTools();
      expect(tools.map((BaseTool tool) => tool.name).toSet(), <String>{
        'get_dataset_info',
        'get_table_info',
        'list_dataset_ids',
        'list_table_ids',
        'get_job_info',
        'execute_sql',
        'forecast',
        'analyze_contribution',
        'detect_anomalies',
        'ask_data_insights',
      });

      final bigquery_toolset.BigQueryToolset filtered =
          bigquery_toolset.BigQueryToolset(
            toolFilter: <String>['get_job_info'],
          );
      final List<BaseTool> filteredTools = await filtered.getTools();
      expect(filteredTools, hasLength(1));
      expect(filteredTools.single.name, 'get_job_info');
    });

    test(
      'GoogleTool bridge injects credentials/settings into execute_sql',
      () async {
        Object? capturedCredentials;
        final _FakeBigQueryClient client = _FakeBigQueryClient()
          ..onQuery =
              ({
                required String query,
                required String project,
                required BigQueryQueryJobConfig jobConfig,
              }) {
                return _FakeQueryJob(statementType: 'SELECT');
              }
          ..onQueryAndWait =
              ({
                required String query,
                required String project,
                required BigQueryQueryJobConfig jobConfig,
                required int maxResults,
              }) {
                return <Map<String, Object?>>[
                  <String, Object?>{'id': 1},
                ];
              };

        setBigQueryClientFactory(({
          required String? project,
          required Object credentials,
          String? location,
          required List<String> userAgent,
        }) {
          capturedCredentials = credentials;
          return client;
        });

        final bigquery_toolset.BigQueryToolset toolset =
            bigquery_toolset.BigQueryToolset(
              credentialsConfig: BigQueryCredentialsConfig(
                externalAccessTokenKey: 'bq_token',
              ),
              bigqueryToolConfig: BigQueryToolConfig(maxQueryResultRows: 5),
            );

        final BaseTool queryTool = (await toolset.getTools()).singleWhere(
          (BaseTool tool) => tool.name == 'execute_sql',
        );

        final Object? response = await queryTool.run(
          args: <String, dynamic>{'projectId': 'project1', 'query': 'SELECT 1'},
          toolContext: _newToolContext(
            state: <String, Object?>{'bq_token': 'token-abc'},
          ),
        );

        expect(response, isA<Map<String, Object?>>());
        expect((response! as Map<String, Object?>)['status'], 'SUCCESS');
        expect(capturedCredentials, isA<GoogleOAuthCredential>());
      },
    );
  });
}

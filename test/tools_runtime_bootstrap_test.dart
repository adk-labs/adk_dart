import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeBigQueryDatasetListItem implements BigQueryDatasetListItem {
  _FakeBigQueryDatasetListItem(this.datasetId);

  @override
  final String datasetId;
}

class _FakeBigQueryTableListItem implements BigQueryTableListItem {
  _FakeBigQueryTableListItem(this.tableId);

  @override
  final String tableId;
}

class _FakeBigQueryResourceInfo implements BigQueryResourceInfo {
  @override
  Map<String, Object?> toApiRepr() => <String, Object?>{'ok': true};
}

class _FakeBigQueryJobInfo implements BigQueryJobInfo {
  @override
  Map<String, Object?> get properties => <String, Object?>{'ok': true};
}

class _FakeBigQueryQueryJob implements BigQueryQueryJob {
  @override
  String? get statementType => 'SELECT';

  @override
  BigQueryTableReference? get destination => null;

  @override
  BigQuerySessionInfo? get sessionInfo => null;

  @override
  Map<String, Object?> toApiRepr() => <String, Object?>{'ok': true};
}

class _FakeBigQueryClient implements BigQueryClient {
  @override
  BigQueryResourceInfo getDataset(BigQueryDatasetReference reference) {
    return _FakeBigQueryResourceInfo();
  }

  @override
  BigQueryJobInfo getJob(String jobId) {
    return _FakeBigQueryJobInfo();
  }

  @override
  BigQueryResourceInfo getTable(BigQueryTableReference reference) {
    return _FakeBigQueryResourceInfo();
  }

  @override
  Iterable<BigQueryDatasetListItem> listDatasets(String projectId) sync* {
    yield _FakeBigQueryDatasetListItem('dataset');
  }

  @override
  Iterable<BigQueryTableListItem> listTables(
    BigQueryDatasetReference reference,
  ) sync* {
    yield _FakeBigQueryTableListItem('table');
  }

  @override
  BigQueryQueryJob query({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
  }) {
    return _FakeBigQueryQueryJob();
  }

  @override
  Iterable<Map<String, Object?>> queryAndWait({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
    required int maxResults,
  }) sync* {
    yield <String, Object?>{'ok': true};
  }
}

class _FakeBigtableAdminClient implements BigtableAdminClient {
  @override
  BigtableAdminInstance instance(String instanceId) {
    return _FakeBigtableAdminInstance(instanceId);
  }

  @override
  BigtableInstanceListResult listInstances() {
    return const BigtableInstanceListResult(
      instances: <BigtableInstanceSummary>[
        BigtableInstanceSummary(instanceId: 'instance'),
      ],
    );
  }
}

class _FakeBigtableAdminInstance implements BigtableAdminInstance {
  _FakeBigtableAdminInstance(this.instanceId);

  @override
  final String instanceId;

  @override
  String get displayName => 'instance';

  @override
  Map<String, Object?> get labels => <String, Object?>{};

  @override
  Object? get state => 'ready';

  @override
  Object? get type => 'production';

  @override
  Iterable<BigtableTableAdmin> listTables() sync* {
    yield _FakeBigtableTableAdmin('table');
  }

  @override
  void reload() {}

  @override
  BigtableTableAdmin table(String tableId) {
    return _FakeBigtableTableAdmin(tableId);
  }
}

class _FakeBigtableTableAdmin implements BigtableTableAdmin {
  _FakeBigtableTableAdmin(this.tableId);

  @override
  final String tableId;

  @override
  Map<String, Object?> listColumnFamilies() => <String, Object?>{};
}

class _FakeBigtableDataClient implements BigtableDataClient {
  @override
  BigtableQueryIterator executeQuery({
    required String query,
    required String instanceId,
    Map<String, Object?>? parameters,
    Map<String, Object?>? parameterTypes,
  }) {
    return _FakeBigtableQueryIterator();
  }
}

class _FakeBigtableQueryIterator extends Iterable<BigtableQueryRow>
    implements BigtableQueryIterator {
  @override
  void close() {}

  @override
  Iterator<BigtableQueryRow> get iterator =>
      <BigtableQueryRow>[_FakeBigtableQueryRow()].iterator;
}

class _FakeBigtableQueryRow implements BigtableQueryRow {
  @override
  Map<String, Object?> get fields => <String, Object?>{'ok': true};
}

class _FakeSpannerClient implements SpannerClient {
  @override
  SpannerInstance instance(String instanceId) {
    return _FakeSpannerInstance();
  }

  @override
  String userAgent = '';
}

class _FakeSpannerInstance implements SpannerInstance {
  @override
  SpannerDatabase database(String databaseId) {
    return _FakeSpannerDatabase();
  }

  @override
  bool exists() => true;
}

class _FakeSpannerDatabase implements SpannerDatabase {
  @override
  SpannerBatch batch() => _FakeSpannerBatch();

  @override
  SpannerDatabaseDialect get databaseDialect =>
      SpannerDatabaseDialect.googleStandardSql;

  @override
  bool exists() => true;

  @override
  Iterable<SpannerTable> listTables({String schema = '_default'}) sync* {}

  @override
  void reload() {}

  @override
  SpannerSnapshot snapshot({bool multiUse = false}) => _FakeSpannerSnapshot();

  @override
  SpannerUpdateDdlOperation updateDdl(List<String> statements) {
    return _FakeSpannerUpdateDdlOperation();
  }
}

class _FakeSpannerSnapshot implements SpannerSnapshot {
  @override
  SpannerResultSet executeSql({
    required String sql,
    Map<String, Object?>? params,
    Map<String, Object?>? paramTypes,
  }) {
    return _FakeSpannerResultSet();
  }
}

class _FakeSpannerResultSet implements SpannerResultSet {
  @override
  Object? one() => null;

  @override
  Iterable<Object?> get rows => const <Object?>[];

  @override
  List<Map<String, Object?>> toDictList() => const <Map<String, Object?>>[];
}

class _FakeSpannerUpdateDdlOperation implements SpannerUpdateDdlOperation {
  @override
  Future<void> result() async {}
}

class _FakeSpannerBatch implements SpannerBatch {
  @override
  void insertOrUpdate({
    required String table,
    required List<String> columns,
    required List<List<Object?>> values,
  }) {}
}

class _FakeToolboxDelegate implements ToolboxToolsetDelegate {
  bool isClosed = false;

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return const <BaseTool>[];
  }
}

InvocationContext _newAudioInvocationContext() {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_runtime_bootstrap',
    agent: LlmAgent(name: 'agent', model: 'gemini-2.5-flash'),
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
  );
}

void main() {
  group('Tool runtime bootstrap', () {
    tearDown(() {
      resetToolRuntimeBootstrap();
    });

    test(
      'configures tool factories and toolbox delegate in one call',
      () async {
        final _FakeToolboxDelegate delegate = _FakeToolboxDelegate();
        configureToolRuntimeBootstrap(
          bigQueryClientFactory:
              ({
                required String? project,
                required Object credentials,
                String? location,
                required List<String> userAgent,
              }) {
                return _FakeBigQueryClient();
              },
          bigtableAdminClientFactory:
              ({
                required String project,
                required Object credentials,
                required String userAgent,
              }) {
                return _FakeBigtableAdminClient();
              },
          bigtableDataClientFactory:
              ({
                required String project,
                required Object credentials,
                required String userAgent,
              }) {
                return _FakeBigtableDataClient();
              },
          spannerClientFactory:
              ({required String project, required Object credentials}) {
                return _FakeSpannerClient();
              },
          toolboxDelegateFactory:
              ({
                required String serverUrl,
                String? toolsetName,
                List<String>? toolNames,
                Map<String, AuthTokenGetter>? authTokenGetters,
                Map<String, Object?>? boundParams,
                Object? credentials,
                Map<String, String>? additionalHeaders,
                Map<String, Object?>? additionalOptions,
              }) {
                return delegate;
              },
        );

        final BigQueryClient bigQueryClient = getBigQueryClient(
          project: 'project',
          credentials: Object(),
        );
        expect(bigQueryClient, isA<_FakeBigQueryClient>());

        final BigtableAdminClient bigtableAdminClient = getBigtableAdminClient(
          project: 'project',
          credentials: Object(),
        );
        final BigtableDataClient bigtableDataClient = getBigtableDataClient(
          project: 'project',
          credentials: Object(),
        );
        expect(bigtableAdminClient, isA<_FakeBigtableAdminClient>());
        expect(bigtableDataClient, isA<_FakeBigtableDataClient>());

        final SpannerClient spannerClient = getSpannerClient(
          project: 'project',
          credentials: Object(),
        );
        expect(spannerClient, isA<_FakeSpannerClient>());
        expect(spannerClient.userAgent, spannerUserAgent);

        final ToolboxToolset toolbox = ToolboxToolset(
          serverUrl: 'http://toolbox',
        );
        final List<BaseTool> tools = await toolbox.getTools();
        expect(tools, isEmpty);
        await toolbox.close();
        expect(delegate.isClosed, isTrue);
      },
    );

    test('configures global default audio recognizer', () async {
      configureToolRuntimeBootstrap(
        defaultAudioRecognizer: (List<int> audioData) async {
          return <String>['recognized'];
        },
      );

      final InvocationContext context = _newAudioInvocationContext();
      context.transcriptionCache = <Object?>[
        TranscriptionEntry(
          role: 'user',
          data: InlineData(mimeType: 'audio/wav', data: <int>[1, 2, 3]),
        ),
      ];

      final List<Content> contents = await AudioTranscriber().transcribeFile(
        context,
      );
      expect(contents, hasLength(1));
      expect(contents.first.parts.first.text, 'recognized');
    });

    test('reset restores default fail-fast runtime behavior', () async {
      configureToolRuntimeBootstrap(
        bigQueryClientFactory:
            ({
              required String? project,
              required Object credentials,
              String? location,
              required List<String> userAgent,
            }) {
              return _FakeBigQueryClient();
            },
        bigtableAdminClientFactory:
            ({
              required String project,
              required Object credentials,
              required String userAgent,
            }) {
              return _FakeBigtableAdminClient();
            },
        bigtableDataClientFactory:
            ({
              required String project,
              required Object credentials,
              required String userAgent,
            }) {
              return _FakeBigtableDataClient();
            },
        spannerClientFactory:
            ({required String project, required Object credentials}) {
              return _FakeSpannerClient();
            },
        toolboxDelegateFactory:
            ({
              required String serverUrl,
              String? toolsetName,
              List<String>? toolNames,
              Map<String, AuthTokenGetter>? authTokenGetters,
              Map<String, Object?>? boundParams,
              Object? credentials,
              Map<String, String>? additionalHeaders,
              Map<String, Object?>? additionalOptions,
            }) {
              return _FakeToolboxDelegate();
            },
        defaultAudioRecognizer: (List<int> audioData) async => <String>['ok'],
      );

      resetToolRuntimeBootstrap();

      final BigQueryClient bigQueryClient = getBigQueryClient(
        project: 'project',
        credentials: <String, Object?>{'access_token': 'token'},
      );
      expect(
        bigQueryClient.runtimeType.toString().toLowerCase(),
        contains('bigquery'),
      );

      final BigtableAdminClient bigtableAdminClient = getBigtableAdminClient(
        project: 'project',
        credentials: <String, Object?>{'access_token': 'token'},
      );
      expect(
        bigtableAdminClient.runtimeType.toString().toLowerCase(),
        contains('bigtable'),
      );

      final SpannerClient spannerClient = getSpannerClient(
        project: 'project',
        credentials: <String, Object?>{'access_token': 'token'},
      );
      expect(
        spannerClient.runtimeType.toString().toLowerCase(),
        contains('spanner'),
      );
      expect(
        () => ToolboxToolset(serverUrl: 'http://toolbox'),
        returnsNormally,
      );

      final InvocationContext context = _newAudioInvocationContext();
      context.transcriptionCache = <Object?>[
        TranscriptionEntry(
          role: 'user',
          data: InlineData(mimeType: 'audio/wav', data: <int>[1]),
        ),
      ];
      await expectLater(
        () => AudioTranscriber().transcribeFile(context),
        throwsStateError,
      );
    });
  });
}

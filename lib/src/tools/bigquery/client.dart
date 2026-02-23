import '../../version.dart';

const String bigQueryUserAgent = 'adk-bigquery-tool google-adk/$adkVersion';

class BigQueryDatasetReference {
  const BigQueryDatasetReference({
    required this.projectId,
    required this.datasetId,
  });

  final String projectId;
  final String datasetId;
}

class BigQueryTableReference {
  const BigQueryTableReference({required this.dataset, required this.tableId});

  final BigQueryDatasetReference dataset;
  final String tableId;

  String get projectId => dataset.projectId;

  String get datasetId => dataset.datasetId;
}

class BigQuerySessionInfo {
  const BigQuerySessionInfo({required this.sessionId});

  final String sessionId;
}

class BigQueryConnectionProperty {
  const BigQueryConnectionProperty(this.key, this.value);

  final String key;
  final String value;
}

class BigQueryQueryJobConfig {
  const BigQueryQueryJobConfig({
    this.dryRun = false,
    this.createSession = false,
    this.connectionProperties = const <BigQueryConnectionProperty>[],
    this.labels = const <String, String>{},
    this.maximumBytesBilled,
  });

  final bool dryRun;
  final bool createSession;
  final List<BigQueryConnectionProperty> connectionProperties;
  final Map<String, String> labels;
  final int? maximumBytesBilled;
}

abstract class BigQueryDatasetListItem {
  String get datasetId;
}

abstract class BigQueryTableListItem {
  String get tableId;
}

abstract class BigQueryResourceInfo {
  Map<String, Object?> toApiRepr();
}

abstract class BigQueryJobInfo {
  Map<String, Object?> get properties;
}

abstract class BigQueryQueryJob {
  String? get statementType;

  BigQueryTableReference? get destination;

  BigQuerySessionInfo? get sessionInfo;

  Map<String, Object?> toApiRepr();
}

abstract class BigQueryClient {
  Iterable<BigQueryDatasetListItem> listDatasets(String projectId);

  BigQueryResourceInfo getDataset(BigQueryDatasetReference reference);

  Iterable<BigQueryTableListItem> listTables(
    BigQueryDatasetReference reference,
  );

  BigQueryResourceInfo getTable(BigQueryTableReference reference);

  BigQueryJobInfo getJob(String jobId);

  BigQueryQueryJob query({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
  });

  Iterable<Map<String, Object?>> queryAndWait({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
    required int maxResults,
  });
}

typedef BigQueryClientFactory =
    BigQueryClient Function({
      required String? project,
      required Object credentials,
      String? location,
      required List<String> userAgent,
    });

BigQueryClientFactory _bigQueryClientFactory = _defaultBigQueryClientFactory;

BigQueryClient getBigQueryClient({
  required String? project,
  required Object credentials,
  String? location,
  Object? userAgent,
}) {
  return _bigQueryClientFactory(
    project: project,
    credentials: credentials,
    location: location,
    userAgent: _resolveUserAgents(userAgent),
  );
}

void setBigQueryClientFactory(BigQueryClientFactory factory) {
  _bigQueryClientFactory = factory;
}

void resetBigQueryClientFactory() {
  _bigQueryClientFactory = _defaultBigQueryClientFactory;
}

BigQueryClient _defaultBigQueryClientFactory({
  required String? project,
  required Object credentials,
  String? location,
  required List<String> userAgent,
}) {
  throw StateError(
    'No default BigQuery client is available in adk_dart. '
    'Inject a client with setBigQueryClientFactory().',
  );
}

List<String> _resolveUserAgents(Object? userAgent) {
  final List<String> userAgents = <String>[bigQueryUserAgent];
  if (userAgent is String) {
    final String trimmed = userAgent.trim();
    if (trimmed.isNotEmpty) {
      userAgents.add(trimmed);
    }
    return userAgents;
  }

  if (userAgent is Iterable) {
    for (final Object? value in userAgent) {
      final String text = '$value'.trim();
      if (text.isNotEmpty) {
        userAgents.add(text);
      }
    }
  }

  return userAgents;
}

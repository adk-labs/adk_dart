import 'dart:async';

import '../../version.dart';

const String spannerUserAgent = 'adk-spanner-tool google-adk/$adkVersion';

enum SpannerDatabaseDialect { googleStandardSql, postgresql, unknown }

class SpannerTable {
  const SpannerTable({required this.tableId});

  final String tableId;
}

abstract class SpannerClient {
  SpannerInstance instance(String instanceId);

  String get userAgent;
  set userAgent(String value);
}

abstract class SpannerInstance {
  bool exists();

  SpannerDatabase database(String databaseId);
}

abstract class SpannerDatabase {
  SpannerDatabaseDialect get databaseDialect;

  bool exists();

  Iterable<SpannerTable> listTables({String schema = '_default'});

  SpannerSnapshot snapshot({bool multiUse = false});

  void reload();

  SpannerUpdateDdlOperation updateDdl(List<String> statements);

  SpannerBatch batch();
}

abstract class SpannerSnapshot {
  SpannerResultSet executeSql({
    required String sql,
    Map<String, Object?>? params,
    Map<String, Object?>? paramTypes,
  });
}

abstract class SpannerResultSet {
  Iterable<Object?> get rows;

  List<Map<String, Object?>> toDictList();

  Object? one();
}

abstract class SpannerUpdateDdlOperation {
  FutureOr<void> result();
}

abstract class SpannerBatch {
  void insertOrUpdate({
    required String table,
    required List<String> columns,
    required List<List<Object?>> values,
  });
}

typedef SpannerClientFactory =
    SpannerClient Function({
      required String project,
      required Object credentials,
    });

SpannerClientFactory _spannerClientFactory = _defaultSpannerClientFactory;

SpannerClient getSpannerClient({
  required String project,
  required Object credentials,
}) {
  final SpannerClient spannerClient = _spannerClientFactory(
    project: project,
    credentials: credentials,
  );
  spannerClient.userAgent = spannerUserAgent;
  return spannerClient;
}

void setSpannerClientFactory(SpannerClientFactory factory) {
  _spannerClientFactory = factory;
}

void resetSpannerClientFactory() {
  _spannerClientFactory = _defaultSpannerClientFactory;
}

SpannerClient _defaultSpannerClientFactory({
  required String project,
  required Object credentials,
}) {
  throw UnsupportedError(
    'No default Cloud Spanner client is available in adk_dart. '
    'Inject a client factory with setSpannerClientFactory().',
  );
}

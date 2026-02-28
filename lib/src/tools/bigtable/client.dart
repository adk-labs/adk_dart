import '../../version.dart';

const String bigtableUserAgent = 'adk-bigtable-tool google-adk/$adkVersion';

class BigtableInstanceSummary {
  const BigtableInstanceSummary({required this.instanceId});

  final String instanceId;
}

class BigtableInstanceListResult {
  const BigtableInstanceListResult({
    required this.instances,
    this.failedLocations = const <String>[],
  });

  final List<BigtableInstanceSummary> instances;
  final List<String> failedLocations;
}

abstract class BigtableAdminClient {
  BigtableInstanceListResult listInstances();

  BigtableAdminInstance instance(String instanceId);
}

abstract class BigtableAdminInstance {
  String get instanceId;
  String get displayName;
  Object? get state;
  Object? get type;
  Map<String, Object?> get labels;

  void reload();

  Iterable<BigtableTableAdmin> listTables();

  BigtableTableAdmin table(String tableId);
}

abstract class BigtableTableAdmin {
  String get tableId;

  Map<String, Object?> listColumnFamilies();
}

abstract class BigtableDataClient {
  BigtableQueryIterator executeQuery({
    required String query,
    required String instanceId,
    Map<String, Object?>? parameters,
    Map<String, Object?>? parameterTypes,
  });
}

abstract class BigtableQueryIterator implements Iterable<BigtableQueryRow> {
  void close();
}

abstract class BigtableQueryRow {
  Map<String, Object?> get fields;
}

typedef BigtableAdminClientFactory =
    BigtableAdminClient Function({
      required String project,
      required Object credentials,
      required String userAgent,
    });

typedef BigtableDataClientFactory =
    BigtableDataClient Function({
      required String project,
      required Object credentials,
      required String userAgent,
    });

class BigtableClientFactoryNotConfiguredException implements Exception {
  BigtableClientFactoryNotConfiguredException({
    required this.target,
    String? message,
  }) : message =
           message ??
           'Bigtable $target client factory is not configured in adk_dart. '
               'Call setBigtableClientFactories(...) before invoking Bigtable tools.';

  static const String defaultCode = 'BIGTABLE_CLIENT_FACTORY_NOT_CONFIGURED';
  final String target;
  final String message;

  String get code => defaultCode;

  @override
  String toString() => '$code[$target]: $message';
}

BigtableAdminClientFactory _adminClientFactory = _defaultAdminClientFactory;
BigtableDataClientFactory _dataClientFactory = _defaultDataClientFactory;

BigtableAdminClient getBigtableAdminClient({
  required String project,
  required Object credentials,
}) {
  if (identical(_adminClientFactory, _defaultAdminClientFactory)) {
    throw BigtableClientFactoryNotConfiguredException(target: 'admin');
  }
  return _adminClientFactory(
    project: project,
    credentials: credentials,
    userAgent: bigtableUserAgent,
  );
}

BigtableDataClient getBigtableDataClient({
  required String project,
  required Object credentials,
}) {
  if (identical(_dataClientFactory, _defaultDataClientFactory)) {
    throw BigtableClientFactoryNotConfiguredException(target: 'data');
  }
  return _dataClientFactory(
    project: project,
    credentials: credentials,
    userAgent: bigtableUserAgent,
  );
}

void setBigtableClientFactories({
  BigtableAdminClientFactory? adminClientFactory,
  BigtableDataClientFactory? dataClientFactory,
}) {
  if (adminClientFactory != null) {
    _adminClientFactory = adminClientFactory;
  }
  if (dataClientFactory != null) {
    _dataClientFactory = dataClientFactory;
  }
}

void resetBigtableClientFactories() {
  _adminClientFactory = _defaultAdminClientFactory;
  _dataClientFactory = _defaultDataClientFactory;
}

BigtableAdminClient _defaultAdminClientFactory({
  required String project,
  required Object credentials,
  required String userAgent,
}) {
  throw BigtableClientFactoryNotConfiguredException(target: 'admin');
}

BigtableDataClient _defaultDataClientFactory({
  required String project,
  required Object credentials,
  required String userAgent,
}) {
  throw BigtableClientFactoryNotConfiguredException(target: 'data');
}

/// BigQuery metadata query helpers used by tool handlers.
library;

import 'client.dart';
import 'config.dart';

/// Lists dataset ids available in [projectId].
Future<Object> listDatasetIds({
  required String projectId,
  required Object credentials,
  required Object settings,
}) async {
  try {
    final BigQueryToolConfig toolSettings = BigQueryToolConfig.fromObject(
      settings,
    );
    final BigQueryClient bqClient = getBigQueryClient(
      project: projectId,
      credentials: credentials,
      location: toolSettings.location,
      userAgent: <String?>[
        toolSettings.applicationName,
        'list_dataset_ids',
      ].whereType<String>(),
    );

    return bqClient
        .listDatasets(projectId)
        .map((BigQueryDatasetListItem dataset) => dataset.datasetId)
        .toList(growable: false);
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Returns dataset metadata for [datasetId].
Future<Map<String, Object?>> getDatasetInfo({
  required String projectId,
  required String datasetId,
  required Object credentials,
  required Object settings,
}) async {
  try {
    final BigQueryToolConfig toolSettings = BigQueryToolConfig.fromObject(
      settings,
    );
    final BigQueryClient bqClient = getBigQueryClient(
      project: projectId,
      credentials: credentials,
      location: toolSettings.location,
      userAgent: <String?>[
        toolSettings.applicationName,
        'get_dataset_info',
      ].whereType<String>(),
    );

    return bqClient
        .getDataset(
          BigQueryDatasetReference(projectId: projectId, datasetId: datasetId),
        )
        .toApiRepr();
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Lists table ids in [datasetId].
Future<Object> listTableIds({
  required String projectId,
  required String datasetId,
  required Object credentials,
  required Object settings,
}) async {
  try {
    final BigQueryToolConfig toolSettings = BigQueryToolConfig.fromObject(
      settings,
    );
    final BigQueryClient bqClient = getBigQueryClient(
      project: projectId,
      credentials: credentials,
      location: toolSettings.location,
      userAgent: <String?>[
        toolSettings.applicationName,
        'list_table_ids',
      ].whereType<String>(),
    );

    return bqClient
        .listTables(
          BigQueryDatasetReference(projectId: projectId, datasetId: datasetId),
        )
        .map((BigQueryTableListItem table) => table.tableId)
        .toList(growable: false);
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Returns table metadata for [tableId].
Future<Map<String, Object?>> getTableInfo({
  required String projectId,
  required String datasetId,
  required String tableId,
  required Object credentials,
  required Object settings,
}) async {
  try {
    final BigQueryToolConfig toolSettings = BigQueryToolConfig.fromObject(
      settings,
    );
    final BigQueryClient bqClient = getBigQueryClient(
      project: projectId,
      credentials: credentials,
      location: toolSettings.location,
      userAgent: <String?>[
        toolSettings.applicationName,
        'get_table_info',
      ].whereType<String>(),
    );

    return bqClient
        .getTable(
          BigQueryTableReference(
            dataset: BigQueryDatasetReference(
              projectId: projectId,
              datasetId: datasetId,
            ),
            tableId: tableId,
          ),
        )
        .toApiRepr();
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Returns job metadata for [jobId].
Future<Map<String, Object?>> getJobInfo({
  required String projectId,
  required String jobId,
  required Object credentials,
  required Object settings,
}) async {
  try {
    final BigQueryToolConfig toolSettings = BigQueryToolConfig.fromObject(
      settings,
    );
    final BigQueryClient bqClient = getBigQueryClient(
      project: projectId,
      credentials: credentials,
      location: toolSettings.location,
      userAgent: <String?>[
        toolSettings.applicationName,
        'get_job_info',
      ].whereType<String>(),
    );

    return bqClient.getJob(jobId).properties;
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

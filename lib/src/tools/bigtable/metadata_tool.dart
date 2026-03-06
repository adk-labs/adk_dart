/// Bigtable metadata operations exposed as tool-call functions.
library;

import 'client.dart';

/// Lists Bigtable instance IDs for [projectId].
Future<Map<String, Object?>> listInstances({
  required String projectId,
  required Object credentials,
}) async {
  try {
    final BigtableAdminClient btClient = getBigtableAdminClient(
      project: projectId,
      credentials: credentials,
    );
    final BigtableInstanceListResult listed = btClient.listInstances();
    final List<String> instanceIds = listed.instances
        .map((BigtableInstanceSummary instance) => instance.instanceId)
        .toList(growable: false);
    return <String, Object?>{'status': 'SUCCESS', 'results': instanceIds};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Gets metadata for one Bigtable [instanceId].
Future<Map<String, Object?>> getInstanceInfo({
  required String projectId,
  required String instanceId,
  required Object credentials,
}) async {
  try {
    final BigtableAdminClient btClient = getBigtableAdminClient(
      project: projectId,
      credentials: credentials,
    );
    final BigtableAdminInstance instance = btClient.instance(instanceId);
    instance.reload();

    final Map<String, Object?> instanceInfo = <String, Object?>{
      'project_id': projectId,
      'instance_id': instance.instanceId,
      'display_name': instance.displayName,
      'state': instance.state,
      'type': instance.type,
      'labels': Map<String, Object?>.from(instance.labels),
    };
    return <String, Object?>{'status': 'SUCCESS', 'results': instanceInfo};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Lists table IDs in [instanceId].
Future<Map<String, Object?>> listTables({
  required String projectId,
  required String instanceId,
  required Object credentials,
}) async {
  try {
    final BigtableAdminClient btClient = getBigtableAdminClient(
      project: projectId,
      credentials: credentials,
    );
    final BigtableAdminInstance instance = btClient.instance(instanceId);
    final List<String> tableIds = instance
        .listTables()
        .map((BigtableTableAdmin table) => table.tableId)
        .toList(growable: false);
    return <String, Object?>{'status': 'SUCCESS', 'results': tableIds};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Lists cluster IDs in [instanceId].
Future<Map<String, Object?>> listClusters({
  required String projectId,
  required String instanceId,
  required Object credentials,
}) async {
  try {
    final BigtableAdminClient btClient = getBigtableAdminClient(
      project: projectId,
      credentials: credentials,
    );
    final BigtableAdminInstance instance = btClient.instance(instanceId);
    final List<String> clusterIds = instance
        .listClusters()
        .map((BigtableClusterAdmin cluster) => cluster.clusterId)
        .toList(growable: false);
    return <String, Object?>{'status': 'SUCCESS', 'results': clusterIds};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Gets metadata for cluster [clusterId] in [instanceId].
Future<Map<String, Object?>> getClusterInfo({
  required String projectId,
  required String instanceId,
  required String clusterId,
  required Object credentials,
}) async {
  try {
    final BigtableAdminClient btClient = getBigtableAdminClient(
      project: projectId,
      credentials: credentials,
    );
    final BigtableAdminInstance instance = btClient.instance(instanceId);
    final BigtableClusterAdmin cluster = instance.cluster(clusterId);
    cluster.reload();

    final Map<String, Object?> clusterInfo = <String, Object?>{
      'project_id': projectId,
      'instance_id': instance.instanceId,
      'cluster_id': cluster.clusterId,
      'location': cluster.location,
      'state': cluster.state,
      'serve_nodes': cluster.serveNodes,
      'default_storage_type': cluster.defaultStorageType,
    };
    return <String, Object?>{'status': 'SUCCESS', 'results': clusterInfo};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Gets metadata for table [tableId] in [instanceId].
Future<Map<String, Object?>> getTableInfo({
  required String projectId,
  required String instanceId,
  required String tableId,
  required Object credentials,
}) async {
  try {
    final BigtableAdminClient btClient = getBigtableAdminClient(
      project: projectId,
      credentials: credentials,
    );
    final BigtableAdminInstance instance = btClient.instance(instanceId);
    final BigtableTableAdmin table = instance.table(tableId);
    final Map<String, Object?> columnFamilies = table.listColumnFamilies();

    final Map<String, Object?> tableInfo = <String, Object?>{
      'project_id': projectId,
      'instance_id': instance.instanceId,
      'table_id': table.tableId,
      'column_families': columnFamilies.keys.toList(growable: false),
    };
    return <String, Object?>{'status': 'SUCCESS', 'results': tableInfo};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

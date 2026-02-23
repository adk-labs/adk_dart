import 'client.dart';

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

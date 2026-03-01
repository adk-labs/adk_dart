import 'dart:io';

import 'migrate_from_sqlalchemy_pickle.dart';
import 'schema_check_utils.dart';

typedef MigrationFunction =
    Future<void> Function(String sourceDbUrl, String destDbUrl);

final Map<String, (String endVersion, MigrationFunction migrate)> migrations =
    <String, (String, MigrationFunction)>{
      schemaVersion0Pickle: (schemaVersion1Json, migrateFromSqlalchemyPickle),
    };

const String latestVersion = latestSchemaVersion;

Future<void> upgrade(String sourceDbUrl, String destDbUrl) async {
  if (sourceDbUrl == destDbUrl) {
    throw StateError(
      'In-place migration is not supported. '
      'Please provide a different URL for destDbUrl.',
    );
  }

  final String currentVersion = await getDbSchemaVersion(sourceDbUrl);
  if (currentVersion == latestVersion) {
    return;
  }

  final List<(String endVersion, MigrationFunction migrate)> migrationPath =
      <(String, MigrationFunction)>[];
  String version = currentVersion;
  while (migrations.containsKey(version) && version != latestVersion) {
    final (String endVersion, MigrationFunction migrate) = migrations[version]!;
    migrationPath.add((endVersion, migrate));
    version = endVersion;
  }

  if (migrationPath.isEmpty) {
    throw StateError(
      'Could not find migration path for schema version '
      '$currentVersion to $latestVersion.',
    );
  }

  String inputUrl = sourceDbUrl;
  final List<File> tempFiles = <File>[];

  try {
    for (int i = 0; i < migrationPath.length; i += 1) {
      final (String _, MigrationFunction migrate) = migrationPath[i];
      final bool isLastStep = i == migrationPath.length - 1;
      late final String outputUrl;
      if (isLastStep) {
        outputUrl = destDbUrl;
      } else {
        final File temp = File(
          '${Directory.systemTemp.path}/adk_session_migration_$i'
          '_${DateTime.now().microsecondsSinceEpoch}.db',
        );
        tempFiles.add(temp);
        outputUrl = 'sqlite:///${temp.path}';
      }

      await migrate(inputUrl, outputUrl);
      inputUrl = outputUrl;
    }
  } finally {
    for (final File file in tempFiles) {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}

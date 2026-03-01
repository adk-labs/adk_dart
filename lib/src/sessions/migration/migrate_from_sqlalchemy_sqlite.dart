import 'migrate_from_sqlalchemy_pickle.dart';
import 'schema_check_utils.dart';
import 'sqlite_db.dart';

Future<void> migrateFromSqlalchemySqlite(
  String sourceDbUrl,
  String destDbPath,
) async {
  final String destinationUrl = destDbPath.startsWith('sqlite:')
      ? destDbPath
      : destDbPath == ':memory:'
      ? ':memory:'
      : 'sqlite:///$destDbPath';
  await migrateFromSqlalchemyPickle(sourceDbUrl, destinationUrl);

  // Python's sqlite-specific migrator writes only runtime tables and does not
  // persist adk_internal_metadata.
  final ResolvedSqliteDbUrl destination = resolveSqliteDbUrl(
    toSyncUrl(destinationUrl),
    argumentName: 'destDbPath',
  );
  final SqliteMigrationDatabase db = SqliteMigrationDatabase.open(
    connectPath: destination.connectPath,
    displayPath: destination.storePath,
    uri: destination.connectUri,
    readOnly: false,
  );
  try {
    db.execute('DROP TABLE IF EXISTS adk_internal_metadata');
  } finally {
    db.dispose();
  }
}

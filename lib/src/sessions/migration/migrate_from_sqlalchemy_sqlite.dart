import 'migrate_from_sqlalchemy_pickle.dart';

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
}

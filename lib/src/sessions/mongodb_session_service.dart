/// MongoDB-backed session service implementation for ADK.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../errors/already_exists_error.dart';
import '../errors/stale_session_error.dart';
import '../events/event.dart';
import '../features/_feature_registry.dart';
import '../platform/time.dart';
import '../platform/uuid.dart';
import 'base_session_service.dart';
import 'schemas/v1.dart';
import 'session.dart';
import 'session_util.dart';
import 'state.dart';

const String _defaultDatabaseName = 'adk_sessions';
const String _defaultSessionsCollection = 'sessions';
const String _defaultEventsCollection = 'events';
const String _defaultAppStatesCollection = 'app_states';
const String _defaultUserStatesCollection = 'user_states';

const String _staleSessionErrorMessage =
    'The provided session was modified in storage after it was fetched. '
    'Please reload the session before appending more events.';

/// Exception thrown when inserting a document with a duplicate `_id`.
class MongoDbDuplicateKeyException implements Exception {
  /// Creates a duplicate-key exception with [message].
  const MongoDbDuplicateKeyException([
    this.message = 'E11000 duplicate key error collection',
  ]);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'MongoDbDuplicateKeyException: $message';
}

/// Result returned by [MongoDbSessionCollection.updateOne].
class MongoDbUpdateResult {
  /// Creates an update result.
  const MongoDbUpdateResult({
    required this.matchedCount,
    required this.modifiedCount,
    this.upsertedId,
  });

  /// Number of documents matched by the filter.
  final int matchedCount;

  /// Number of documents modified by the update.
  final int modifiedCount;

  /// Identifier of the upserted document when `upsert: true` inserted a row.
  final Object? upsertedId;
}

/// Collection interface used by [MongoDbSessionService].
abstract class MongoDbSessionCollection {
  /// Collection name.
  String get name;

  /// Creates an index over [keys] (`1` for ascending, `-1` for descending).
  Future<String> createIndex(List<(String, int)> keys, {String? name});

  /// Finds a single document matching [filter], optionally applying [projection].
  Future<Map<String, Object?>?> findOne(
    Map<String, Object?> filter, {
    Map<String, Object?>? projection,
  });

  /// Finds documents matching [filter] with optional [projection], [sort], and [limit].
  Future<List<Map<String, Object?>>> find(
    Map<String, Object?> filter, {
    Map<String, Object?>? projection,
    List<(String, int)>? sort,
    int? limit,
  });

  /// Inserts a single [document] into the collection.
  ///
  /// Throws [MongoDbDuplicateKeyException] if a document with the same `_id`
  /// already exists.
  Future<void> insertOne(Map<String, Object?> document);

  /// Updates a single document matching [filter] using [update].
  ///
  /// When [upsert] is `true` and no document matches [filter], inserts a new
  /// document initialized from [filter] and [update].
  Future<MongoDbUpdateResult> updateOne(
    Map<String, Object?> filter,
    Map<String, Object?> update, {
    bool upsert = false,
  });

  /// Deletes at most one document matching [filter] and returns the deleted count.
  Future<int> deleteOne(Map<String, Object?> filter);

  /// Deletes all documents matching [filter] and returns the deleted count.
  Future<int> deleteMany(Map<String, Object?> filter);
}

/// Database interface used by [MongoDbSessionService].
abstract class MongoDbSessionDatabase {
  /// Database name.
  String get name;

  /// Returns the collection named [collectionName].
  MongoDbSessionCollection collection(String collectionName);
}

/// Client interface used by [MongoDbSessionService].
abstract class MongoDbSessionClient {
  /// Returns the database named [databaseName].
  MongoDbSessionDatabase database(String databaseName);

  /// Closes the client and releases underlying resources.
  Future<void> close();
}

/// Factory signature for constructing a [MongoDbSessionClient] from a MongoDB URI.
typedef MongoDbSessionClientFactory =
    MongoDbSessionClient Function(
      String dbUrl, {
      Map<String, Object?>? mongoClientKwargs,
    });

MongoDbSessionClientFactory _mongoDbSessionClientFactory =
    _defaultMongoDbSessionClientFactory;

MongoDbSessionClient _defaultMongoDbSessionClientFactory(
  String dbUrl, {
  Map<String, Object?>? mongoClientKwargs,
}) {
  return InMemoryMongoDbSessionClient(
    dbUrl: dbUrl,
    mongoClientKwargs: mongoClientKwargs,
  );
}

/// Overrides the factory used when [MongoDbSessionService] is created from `dbUrl`.
void setMongoDbSessionClientFactory(MongoDbSessionClientFactory factory) {
  _mongoDbSessionClientFactory = factory;
}

/// Restores the default [MongoDbSessionClient] factory.
void resetMongoDbSessionClientFactory() {
  _mongoDbSessionClientFactory = _defaultMongoDbSessionClientFactory;
}

/// Creates a [MongoDbSessionClient] from [dbUrl] using the active factory.
MongoDbSessionClient createMongoDbClientFromUrl(
  String dbUrl, {
  Map<String, Object?>? mongoClientKwargs,
}) {
  return _mongoDbSessionClientFactory(
    dbUrl,
    mongoClientKwargs: mongoClientKwargs,
  );
}

/// In-memory implementation of [MongoDbSessionCollection] for testing and local use.
class InMemoryMongoDbSessionCollection implements MongoDbSessionCollection {
  /// Creates an in-memory MongoDB collection named [name].
  InMemoryMongoDbSessionCollection(this.name);

  @override
  final String name;

  final List<Map<String, Object?>> _documents = <Map<String, Object?>>[];
  final Map<String, List<(String, int)>> _indexes =
      <String, List<(String, int)>>{};

  /// Read-only view of indexes created on this collection.
  Map<String, List<(String, int)>> get indexes =>
      Map<String, List<(String, int)>>.unmodifiable(_indexes);

  /// Read-only snapshot of all documents currently stored in this collection.
  List<Map<String, Object?>> get documents => _documents
      .map((Map<String, Object?> doc) => _deepCopyMap(doc))
      .toList(growable: false);

  @override
  Future<String> createIndex(List<(String, int)> keys, {String? name}) async {
    final String indexName =
        name ??
        keys.map(((String, int) entry) => '${entry.$1}_${entry.$2}').join('_');
    _indexes[indexName] = List<(String, int)>.unmodifiable(keys);
    return indexName;
  }

  @override
  Future<Map<String, Object?>?> findOne(
    Map<String, Object?> filter, {
    Map<String, Object?>? projection,
  }) async {
    for (final Map<String, Object?> doc in _documents) {
      if (_matchesFilter(doc, filter)) {
        final Map<String, Object?> copy = _deepCopyMap(doc);
        return projection == null ? copy : _applyProjection(copy, projection);
      }
    }
    return null;
  }

  @override
  Future<List<Map<String, Object?>>> find(
    Map<String, Object?> filter, {
    Map<String, Object?>? projection,
    List<(String, int)>? sort,
    int? limit,
  }) async {
    List<Map<String, Object?>> matched = _documents
        .where((Map<String, Object?> doc) => _matchesFilter(doc, filter))
        .map(_deepCopyMap)
        .toList();

    if (sort != null && sort.isNotEmpty) {
      matched.sort((Map<String, Object?> a, Map<String, Object?> b) {
        for (final (String field, int direction) in sort) {
          final Object? valA = _getDottedValue(a, field);
          final Object? valB = _getDottedValue(b, field);
          final int cmp = _compareValues(valA, valB);
          if (cmp != 0) {
            return direction < 0 ? -cmp : cmp;
          }
        }
        return 0;
      });
    }

    if (limit != null) {
      if (limit <= 0) {
        matched = <Map<String, Object?>>[];
      } else if (matched.length > limit) {
        matched = matched.sublist(0, limit);
      }
    }

    if (projection != null) {
      matched = matched
          .map((Map<String, Object?> doc) => _applyProjection(doc, projection))
          .toList();
    }
    return matched;
  }

  @override
  Future<void> insertOne(Map<String, Object?> document) async {
    final Map<String, Object?> copy = _deepCopyMap(document);
    if (copy.containsKey('_id')) {
      final Object? id = copy['_id'];
      for (final Map<String, Object?> existing in _documents) {
        if (_deepEquals(existing['_id'], id)) {
          throw const MongoDbDuplicateKeyException();
        }
      }
    } else {
      copy['_id'] = newUuid();
    }
    _documents.add(copy);
  }

  @override
  Future<MongoDbUpdateResult> updateOne(
    Map<String, Object?> filter,
    Map<String, Object?> update, {
    bool upsert = false,
  }) async {
    for (int i = 0; i < _documents.length; i += 1) {
      final Map<String, Object?> doc = _documents[i];
      if (_matchesFilter(doc, filter)) {
        _applyUpdate(doc, update);
        return const MongoDbUpdateResult(matchedCount: 1, modifiedCount: 1);
      }
    }

    if (!upsert) {
      return const MongoDbUpdateResult(matchedCount: 0, modifiedCount: 0);
    }

    final Map<String, Object?> newDoc = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in filter.entries) {
      if (!entry.key.startsWith(r'$') && entry.value is! Map) {
        _setDottedValue(newDoc, entry.key, _deepCopyValue(entry.value));
      } else if (entry.key == '_id') {
        newDoc['_id'] = _deepCopyValue(entry.value);
      }
    }
    if (!newDoc.containsKey('_id')) {
      newDoc['_id'] = newUuid();
    }
    _applyUpdate(newDoc, update);
    _documents.add(newDoc);
    return MongoDbUpdateResult(
      matchedCount: 0,
      modifiedCount: 0,
      upsertedId: _deepCopyValue(newDoc['_id']),
    );
  }

  @override
  Future<int> deleteOne(Map<String, Object?> filter) async {
    for (int i = 0; i < _documents.length; i += 1) {
      if (_matchesFilter(_documents[i], filter)) {
        _documents.removeAt(i);
        return 1;
      }
    }
    return 0;
  }

  @override
  Future<int> deleteMany(Map<String, Object?> filter) async {
    int removed = 0;
    _documents.removeWhere((Map<String, Object?> doc) {
      if (_matchesFilter(doc, filter)) {
        removed += 1;
        return true;
      }
      return false;
    });
    return removed;
  }
}

/// In-memory implementation of [MongoDbSessionDatabase].
class InMemoryMongoDbSessionDatabase implements MongoDbSessionDatabase {
  /// Creates an in-memory MongoDB database named [name].
  InMemoryMongoDbSessionDatabase(this.name);

  @override
  final String name;

  final Map<String, InMemoryMongoDbSessionCollection> _collections =
      <String, InMemoryMongoDbSessionCollection>{};

  @override
  InMemoryMongoDbSessionCollection collection(String collectionName) {
    return _collections.putIfAbsent(
      collectionName,
      () => InMemoryMongoDbSessionCollection(collectionName),
    );
  }
}

/// In-memory implementation of [MongoDbSessionClient].
class InMemoryMongoDbSessionClient implements MongoDbSessionClient {
  /// Creates an in-memory MongoDB session client.
  InMemoryMongoDbSessionClient({this.dbUrl, this.mongoClientKwargs});

  /// Optional connection URI used to create this client.
  final String? dbUrl;

  /// Optional driver keyword arguments passed when constructing this client.
  final Map<String, Object?>? mongoClientKwargs;

  /// Whether [close] has been called on this client.
  bool isClosed = false;

  final Map<String, InMemoryMongoDbSessionDatabase> _databases =
      <String, InMemoryMongoDbSessionDatabase>{};

  @override
  InMemoryMongoDbSessionDatabase database(String databaseName) {
    return _databases.putIfAbsent(
      databaseName,
      () => InMemoryMongoDbSessionDatabase(databaseName),
    );
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }
}

/// Session storage service backed by MongoDB collections.
///
/// Stores sessions, events, application state, and user state in four distinct
/// MongoDB collections within a database, with optimistic concurrency checks
/// on session updates.
///
/// ```dart
/// final client = InMemoryMongoDbSessionClient();
/// final service = MongoDbSessionService(
///   client: client,
///   databaseName: 'adk_sessions',
/// );
/// final session = await service.createSession(
///   appName: 'my_app',
///   userId: 'user_1',
///   state: {'counter': 1},
/// );
/// ```
class MongoDbSessionService extends BaseSessionService {
  /// Creates a MongoDB-backed session service.
  ///
  /// Exactly one of [dbUrl] or [client] must be provided. When [client] is
  /// provided, [databaseName] is required. When [dbUrl] is provided, the URI
  /// scheme must be `mongodb://` or `mongodb+srv://`, and [databaseName] is
  /// resolved from [databaseName], the URI path, or `'adk_sessions'`.
  MongoDbSessionService({
    String? dbUrl,
    String? databaseName,
    MongoDbSessionClient? client,
    this.sessionsCollection = _defaultSessionsCollection,
    this.eventsCollection = _defaultEventsCollection,
    this.appStatesCollection = _defaultAppStatesCollection,
    this.userStatesCollection = _defaultUserStatesCollection,
    Map<String, Object?>? mongoClientKwargs,
  }) : mongoClientKwargs = mongoClientKwargs == null
           ? null
           : Map<String, Object?>.unmodifiable(mongoClientKwargs) {
    warnFeatureUse(FeatureName.mongodbSessionService);

    final bool hasDbUrl = dbUrl != null;
    final bool hasClient = client != null;
    if (hasDbUrl == hasClient) {
      throw ArgumentError(
        'Exactly one of `dbUrl` or `client` must be provided.',
      );
    }

    if (databaseName != null && databaseName.trim().isEmpty) {
      throw ArgumentError.value(
        databaseName,
        'databaseName',
        'Database name must be a non-empty string.',
      );
    }

    final Map<String, String> collectionNames = <String, String>{
      'sessionsCollection': sessionsCollection,
      'eventsCollection': eventsCollection,
      'appStatesCollection': appStatesCollection,
      'userStatesCollection': userStatesCollection,
    };
    for (final MapEntry<String, String> entry in collectionNames.entries) {
      if (entry.value.trim().isEmpty) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          '${entry.key} must be a non-empty string.',
        );
      }
    }
    if (collectionNames.values.toSet().length != collectionNames.length) {
      throw ArgumentError(
        'Collection names must be distinct: '
        '${collectionNames.values.toList(growable: false)}.',
      );
    }

    if (client != null) {
      if (databaseName == null || databaseName.trim().isEmpty) {
        throw ArgumentError(
          '`databaseName` is required when `client` is provided.',
        );
      }
      _client = client;
      _ownsClient = false;
      _dbUrl = null;
      _databaseName = databaseName.trim();
    } else {
      final String trimmedUrl = dbUrl!.trim();
      if (trimmedUrl.isEmpty) {
        throw ArgumentError.value(
          dbUrl,
          'dbUrl',
          '`dbUrl` must be a non-empty string.',
        );
      }
      if (!trimmedUrl.startsWith('mongodb://') &&
          !trimmedUrl.startsWith('mongodb+srv://')) {
        throw ArgumentError.value(
          dbUrl,
          'dbUrl',
          'Invalid MongoDB URI scheme; expected `mongodb://` or `mongodb+srv://`.',
        );
      }
      _dbUrl = trimmedUrl;
      _databaseName =
          databaseName?.trim() ??
          _extractDatabaseFromUri(trimmedUrl) ??
          _defaultDatabaseName;
      _client = _mongoDbSessionClientFactory(
        trimmedUrl,
        mongoClientKwargs: this.mongoClientKwargs,
      );
      _ownsClient = true;
    }

    _db = _client.database(_databaseName);
    _sessions = _db.collection(sessionsCollection);
    _events = _db.collection(eventsCollection);
    _appStates = _db.collection(appStatesCollection);
    _userStates = _db.collection(userStatesCollection);
  }

  /// Collection name used for session documents.
  final String sessionsCollection;

  /// Collection name used for event documents.
  final String eventsCollection;

  /// Collection name used for application-level state documents.
  final String appStatesCollection;

  /// Collection name used for user-level state documents.
  final String userStatesCollection;

  /// Optional extra options forwarded to the MongoDB client constructor.
  final Map<String, Object?>? mongoClientKwargs;

  late final MongoDbSessionClient _client;
  late final bool _ownsClient;
  late final String? _dbUrl;
  late final String _databaseName;
  late final MongoDbSessionDatabase _db;
  late final MongoDbSessionCollection _sessions;
  late final MongoDbSessionCollection _events;
  late final MongoDbSessionCollection _appStates;
  late final MongoDbSessionCollection _userStates;

  bool _indexesEnsured = false;
  Future<void>? _ensureIndexesFuture;
  bool _isClosed = false;

  /// Underlying MongoDB session client.
  MongoDbSessionClient get client => _client;

  /// Whether this service owns [client] and closes it on [close].
  bool get ownsClient => _ownsClient;

  /// Connection URL if constructed with `dbUrl`, otherwise `null`.
  String? get dbUrl => _dbUrl;

  /// Resolved MongoDB database name.
  String get databaseName => _databaseName;

  /// Whether [close] has been called on this service.
  bool get isClosed => _isClosed;

  static String? _extractDatabaseFromUri(String uri) {
    final int schemeEnd = uri.indexOf('://');
    if (schemeEnd < 0) {
      return null;
    }
    final String afterScheme = uri.substring(schemeEnd + 3);
    final int slashIndex = afterScheme.indexOf('/');
    if (slashIndex < 0) {
      return null;
    }
    String pathPart = afterScheme.substring(slashIndex + 1);
    final int queryIndex = pathPart.indexOf('?');
    if (queryIndex >= 0) {
      pathPart = pathPart.substring(0, queryIndex);
    }
    final String trimmedPath = pathPart.replaceAll(RegExp(r'^/+|/+$'), '').trim();
    if (trimmedPath.isEmpty) {
      return null;
    }
    return Uri.decodeComponent(trimmedPath);
  }

  Future<void> _ensureIndexes() async {
    if (_indexesEnsured) {
      return;
    }
    if (_ensureIndexesFuture != null) {
      await _ensureIndexesFuture;
      return;
    }
    final Completer<void> completer = Completer<void>();
    _ensureIndexesFuture = completer.future;
    try {
      await _events.createIndex(
        const <(String, int)>[
          ('app_name', 1),
          ('user_id', 1),
          ('session_id', 1),
          ('timestamp', -1),
        ],
        name: 'app_user_session_ts',
      );
      await _sessions.createIndex(
        const <(String, int)>[
          ('app_name', 1),
          ('user_id', 1),
          ('update_time', -1),
        ],
        name: 'app_user_updated',
      );
      _indexesEnsured = true;
      completer.complete();
    } catch (error, stackTrace) {
      _ensureIndexesFuture = null;
      completer.completeError(error, stackTrace);
      rethrow;
    }
  }

  static Map<String, Object?> _sessionDocId(
    String appName,
    String userId,
    String sessionId,
  ) => <String, Object?>{
    'app_name': appName,
    'user_id': userId,
    'id': sessionId,
  };

  static Map<String, Object?> _eventDocId(
    String appName,
    String userId,
    String sessionId,
    String eventId,
  ) => <String, Object?>{
    'app_name': appName,
    'user_id': userId,
    'session_id': sessionId,
    'id': eventId,
  };

  static Map<String, Object?> _appStateDocId(String appName) =>
      <String, Object?>{'app_name': appName};

  static Map<String, Object?> _userStateDocId(String appName, String userId) =>
      <String, Object?>{'app_name': appName, 'user_id': userId};

  Future<Map<String, Object?>> _fetchAppState(String appName) async {
    final Map<String, Object?>? doc = await _appStates.findOne(
      <String, Object?>{'_id': _appStateDocId(appName)},
      projection: const <String, Object?>{'state': 1},
    );
    if (doc == null) {
      return <String, Object?>{};
    }
    return _deepCopyMap(_asStringObjectMap(doc['state']));
  }

  Future<Map<String, Object?>> _fetchUserState(
    String appName,
    String userId,
  ) async {
    final Map<String, Object?>? doc = await _userStates.findOne(
      <String, Object?>{'_id': _userStateDocId(appName, userId)},
      projection: const <String, Object?>{'state': 1},
    );
    if (doc == null) {
      return <String, Object?>{};
    }
    return _deepCopyMap(_asStringObjectMap(doc['state']));
  }

  /// Returns the stored user-scoped state map for [appName] and [userId].
  @override
  Future<Map<String, Object?>> getUserState({
    required String appName,
    required String userId,
  }) async {
    await _ensureIndexes();
    return _fetchUserState(appName, userId);
  }

  /// Returns the stored app-scoped state map for [appName].
  Future<Map<String, Object?>> getAppState({required String appName}) async {
    await _ensureIndexes();
    return _fetchAppState(appName);
  }

  Future<void> _applyAppStateDelta(
    String appName,
    Map<String, Object?> delta,
    double now,
  ) async {
    if (delta.isEmpty) {
      return;
    }
    final Map<String, Object?> setFields = <String, Object?>{
      'app_name': appName,
      'update_time': now,
      for (final MapEntry<String, Object?> entry in delta.entries)
        'state.${entry.key}': _deepCopyValue(entry.value),
    };
    await _appStates.updateOne(
      <String, Object?>{'_id': _appStateDocId(appName)},
      <String, Object?>{r'$set': setFields},
      upsert: true,
    );
  }

  Future<void> _applyUserStateDelta(
    String appName,
    String userId,
    Map<String, Object?> delta,
    double now,
  ) async {
    if (delta.isEmpty) {
      return;
    }
    final Map<String, Object?> setFields = <String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'update_time': now,
      for (final MapEntry<String, Object?> entry in delta.entries)
        'state.${entry.key}': _deepCopyValue(entry.value),
    };
    await _userStates.updateOne(
      <String, Object?>{'_id': _userStateDocId(appName, userId)},
      <String, Object?>{r'$set': setFields},
      upsert: true,
    );
  }

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    if (sessionId != null && sessionId.trim().isEmpty) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        'sessionId cannot be an empty or whitespace-only string.',
      );
    }

    await _ensureIndexes();

    final String resolvedSessionId =
        (sessionId != null && sessionId.trim().isNotEmpty)
        ? sessionId
        : newUuid();

    final SessionStateDelta deltas = extractStateDelta(state);

    final double now = getTime();
    final String revisionId = newUuid();

    final Map<String, Object?> sessionDoc = <String, Object?>{
      '_id': _sessionDocId(appName, userId, resolvedSessionId),
      'app_name': appName,
      'user_id': userId,
      'id': resolvedSessionId,
      'state': _deepCopyMap(deltas.session),
      'create_time': now,
      'update_time': now,
      'revision_id': revisionId,
    };

    try {
      await _sessions.insertOne(sessionDoc);
    } on MongoDbDuplicateKeyException {
      throw AlreadyExistsError(
        'Session with id $resolvedSessionId already exists.',
      );
    }

    await _applyAppStateDelta(appName, deltas.app, now);
    await _applyUserStateDelta(appName, userId, deltas.user, now);

    final Map<String, Object?> appState = await _fetchAppState(appName);
    final Map<String, Object?> userState = await _fetchUserState(
      appName,
      userId,
    );
    final Map<String, Object?> mergedState = _mergeState(
      appState,
      userState,
      deltas.session,
    );

    return Session(
      id: resolvedSessionId,
      appName: appName,
      userId: userId,
      state: mergedState,
      events: <Event>[],
      lastUpdateTime: now,
      storageUpdateMarker: revisionId,
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    await _ensureIndexes();

    final Map<String, Object?>? sessionDoc = await _sessions.findOne(
      <String, Object?>{'_id': _sessionDocId(appName, userId, sessionId)},
    );
    if (sessionDoc == null) {
      return null;
    }

    final Map<String, Object?> eventFilter = <String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'session_id': sessionId,
    };
    if (config?.afterTimestamp != null) {
      eventFilter['timestamp'] = <String, Object?>{
        r'$gte': config!.afterTimestamp,
      };
    }

    List<Map<String, Object?>> eventDocs;
    if (config?.numRecentEvents != null && config!.numRecentEvents! <= 0) {
      eventDocs = <Map<String, Object?>>[];
    } else {
      eventDocs = await _events.find(
        eventFilter,
        projection: const <String, Object?>{
          '_id': 0,
          'id': 1,
          'invocation_id': 1,
          'timestamp': 1,
          'event_data': 1,
        },
        sort: const <(String, int)>[('timestamp', -1)],
        limit: config?.numRecentEvents,
      );
    }

    final List<Event> events = eventDocs.reversed
        .map(_decodeEventDoc)
        .toList();

    final Map<String, Object?> appState = await _fetchAppState(appName);
    final Map<String, Object?> userState = await _fetchUserState(
      appName,
      userId,
    );
    final Map<String, Object?> sessionState = _asStringObjectMap(
      sessionDoc['state'],
    );
    final Map<String, Object?> mergedState = _mergeState(
      appState,
      userState,
      sessionState,
    );

    final Object? updateTimeRaw = sessionDoc['update_time'];
    final double lastUpdateTime = _toSeconds(updateTimeRaw);
    final String? marker =
        sessionDoc['revision_id']?.toString() ??
        _formatUpdateMarker(updateTimeRaw);

    return Session(
      id: sessionId,
      appName: appName,
      userId: userId,
      state: mergedState,
      events: events,
      lastUpdateTime: lastUpdateTime,
      storageUpdateMarker: marker,
    );
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    await _ensureIndexes();

    final Map<String, Object?> filter = <String, Object?>{'app_name': appName};
    if (userId != null) {
      filter['user_id'] = userId;
    }

    final List<Map<String, Object?>> sessionDocs = await _sessions.find(
      filter,
      sort: const <(String, int)>[('update_time', -1)],
    );
    if (sessionDocs.isEmpty) {
      return ListSessionsResponse(sessions: <Session>[]);
    }

    final Map<String, Object?> appState = await _fetchAppState(appName);
    final Map<String, Map<String, Object?>> userStatesByUser =
        <String, Map<String, Object?>>{};
    if (userId != null) {
      userStatesByUser[userId] = await _fetchUserState(appName, userId);
    } else {
      final List<Map<String, Object?>> userDocs = await _userStates.find(
        <String, Object?>{'_id.app_name': appName},
      );
      for (final Map<String, Object?> userDoc in userDocs) {
        final Map<String, Object?> idMap = _asStringObjectMap(userDoc['_id']);
        final String? docUserId =
            (idMap['user_id'] ?? userDoc['user_id'])?.toString();
        if (docUserId != null) {
          userStatesByUser[docUserId] = _asStringObjectMap(userDoc['state']);
        }
      }
    }

    final List<Session> sessions = <Session>[];
    for (final Map<String, Object?> doc in sessionDocs) {
      final String docUserId = '${doc['user_id'] ?? ''}';
      final String docSessionId = '${doc['id'] ?? ''}';
      final Map<String, Object?> sessionState = _asStringObjectMap(
        doc['state'],
      );
      final Map<String, Object?> userState =
          userStatesByUser[docUserId] ?? const <String, Object?>{};
      final Map<String, Object?> mergedState = _mergeState(
        appState,
        userState,
        sessionState,
      );
      final Object? updateTimeRaw = doc['update_time'];
      final double lastUpdateTime = _toSeconds(updateTimeRaw);
      final String? marker =
          doc['revision_id']?.toString() ?? _formatUpdateMarker(updateTimeRaw);

      sessions.add(
        Session(
          id: docSessionId,
          appName: appName,
          userId: docUserId,
          state: mergedState,
          events: <Event>[],
          lastUpdateTime: lastUpdateTime,
          storageUpdateMarker: marker,
        ),
      );
    }

    return ListSessionsResponse(sessions: sessions);
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    await _ensureIndexes();

    await _events.deleteMany(<String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'session_id': sessionId,
    });
    await _sessions.deleteOne(<String, Object?>{
      '_id': _sessionDocId(appName, userId, sessionId),
    });
  }

  @override
  Future<Event> appendEvent({
    required Session session,
    required Event event,
  }) async {
    if (event.partial == true) {
      return event;
    }

    await _ensureIndexes();

    final Event trimmedEvent = eventForPersistence(event);
    final Map<String, Object?> sessionDocId = _sessionDocId(
      session.appName,
      session.userId,
      session.id,
    );

    final Map<String, Object?>? storedSession = await _sessions.findOne(
      <String, Object?>{'_id': sessionDocId},
      projection: const <String, Object?>{'update_time': 1, 'revision_id': 1},
    );
    if (storedSession == null) {
      throw StateError(
        'Session ${session.id} not found in MongoDB; cannot append event.',
      );
    }

    final String? storedRevisionId = storedSession['revision_id']?.toString();
    final Object? storedUpdateTimeRaw = storedSession['update_time'];
    final double storedUpdateTime = _toSeconds(storedUpdateTimeRaw);
    final String? storedUpdateTimeMarker = _formatUpdateMarker(
      storedUpdateTimeRaw,
    );

    if (session.storageUpdateMarker != null) {
      if (storedRevisionId != null) {
        final bool matchesRevision =
            session.storageUpdateMarker == storedRevisionId;
        final bool matchesTimestampMarker =
            session.storageUpdateMarker == storedUpdateTimeMarker;
        if (!matchesRevision && !matchesTimestampMarker) {
          throw StaleSessionError(_staleSessionErrorMessage);
        }
        if (matchesRevision &&
            (storedUpdateTime - session.lastUpdateTime).abs() > 1e-6) {
          throw StaleSessionError(_staleSessionErrorMessage);
        }
      } else if (session.storageUpdateMarker != storedUpdateTimeMarker) {
        throw StaleSessionError(_staleSessionErrorMessage);
      }
    } else if (storedUpdateTime > session.lastUpdateTime + 1e-6) {
      throw StaleSessionError(_staleSessionErrorMessage);
    }

    final SessionStateDelta deltas = extractStateDelta(
      trimmedEvent.actions.stateDelta,
    );

    final double updateTime = math.max(
      trimmedEvent.timestamp,
      storedUpdateTime,
    );
    final String nextRevisionId = newUuid();

    final Map<String, Object?> sessionSet = <String, Object?>{
      'update_time': updateTime,
      'revision_id': nextRevisionId,
      for (final MapEntry<String, Object?> entry in deltas.session.entries)
        'state.${entry.key}': _deepCopyValue(entry.value),
    };

    final Map<String, Object?> conditionalFilter = <String, Object?>{
      '_id': sessionDocId,
      'revision_id': ?storedRevisionId,
      'update_time': ?storedUpdateTimeRaw,
    };

    final MongoDbUpdateResult updateResult = await _sessions.updateOne(
      conditionalFilter,
      <String, Object?>{r'$set': sessionSet},
    );
    if (updateResult.matchedCount == 0) {
      throw StaleSessionError(_staleSessionErrorMessage);
    }

    await _applyAppStateDelta(session.appName, deltas.app, updateTime);
    await _applyUserStateDelta(
      session.appName,
      session.userId,
      deltas.user,
      updateTime,
    );

    final Map<String, Object?> eventDoc = <String, Object?>{
      '_id': _eventDocId(
        session.appName,
        session.userId,
        session.id,
        trimmedEvent.id,
      ),
      'id': trimmedEvent.id,
      'app_name': session.appName,
      'user_id': session.userId,
      'session_id': session.id,
      'invocation_id': trimmedEvent.invocationId,
      'timestamp': trimmedEvent.timestamp,
      'event_data': encodeEventData(trimmedEvent),
    };
    await _events.updateOne(
      <String, Object?>{'_id': eventDoc['_id']},
      <String, Object?>{r'$set': eventDoc},
      upsert: true,
    );

    session.lastUpdateTime = updateTime;
    session.storageUpdateMarker = nextRevisionId;

    return super.appendEvent(session: session, event: trimmedEvent);
  }

  /// Closes the underlying MongoDB client if owned by this service.
  Future<void> close() async {
    _isClosed = true;
    if (_ownsClient) {
      await _client.close();
    }
  }
}

Event _decodeEventDoc(Map<String, Object?> doc) {
  final Object? rawEventData = doc['event_data'];
  Map<String, Object?> eventData;
  if (rawEventData is String && rawEventData.isNotEmpty) {
    final Object? decoded = jsonDecode(rawEventData);
    eventData = _asStringObjectMap(decoded);
  } else {
    eventData = _asStringObjectMap(rawEventData);
  }
  final String? id = doc['id']?.toString();
  final String? invocationId = doc['invocation_id']?.toString();
  final double? timestamp = doc['timestamp'] == null
      ? null
      : _toSeconds(doc['timestamp']);
  return decodeEventData(
    eventData,
    id: id,
    invocationId: invocationId,
    timestamp: timestamp,
  );
}

Map<String, Object?> _mergeState(
  Map<String, Object?> appState,
  Map<String, Object?> userState,
  Map<String, Object?> sessionState,
) {
  final Map<String, Object?> merged = _deepCopyMap(sessionState);
  for (final MapEntry<String, Object?> entry in appState.entries) {
    merged['${State.appPrefix}${entry.key}'] = _deepCopyValue(entry.value);
  }
  for (final MapEntry<String, Object?> entry in userState.entries) {
    merged['${State.userPrefix}${entry.key}'] = _deepCopyValue(entry.value);
  }
  return merged;
}

double _dateTimeToSeconds(DateTime value) {
  return value.toUtc().microsecondsSinceEpoch / Duration.microsecondsPerSecond;
}

double _toSeconds(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is DateTime) {
    return _dateTimeToSeconds(value);
  }
  if (value is String) {
    final double? asDouble = double.tryParse(value);
    if (asDouble != null) {
      return asDouble;
    }
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return _dateTimeToSeconds(parsed);
    }
  }
  return getTime();
}

String? _formatUpdateMarker(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is num) {
    return value.toDouble().toStringAsFixed(6);
  }
  return '$value';
}

Map<String, Object?> _asStringObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry('$key', _deepCopyValue(item)),
    );
  }
  return <String, Object?>{};
}

Object? _deepCopyValue(Object? value) {
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry('$key', _deepCopyValue(item)),
    );
  }
  if (value is List) {
    return value.map(_deepCopyValue).toList();
  }
  return value;
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> map) {
  return map.map(
    (String key, Object? value) => MapEntry(key, _deepCopyValue(value)),
  );
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is num && b is num) {
    return a == b;
  }
  if (a is DateTime && b is DateTime) {
    return a.isAtSameMomentAs(b);
  }
  if (a is DateTime && b is num) {
    return (_dateTimeToSeconds(a) - b.toDouble()).abs() < 1e-6;
  }
  if (a is num && b is DateTime) {
    return (a.toDouble() - _dateTimeToSeconds(b)).abs() < 1e-6;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final MapEntry<Object?, Object?> entry in a.entries) {
      if (!b.containsKey(entry.key) ||
          !_deepEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i += 1) {
      if (!_deepEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

Object? _getDottedValue(Map<String, Object?> doc, String key) {
  if (doc.containsKey(key)) {
    return doc[key];
  }
  final List<String> parts = key.split('.');
  Object? current = doc;
  for (final String part in parts) {
    if (current is Map && current.containsKey(part)) {
      current = current[part];
    } else {
      return null;
    }
  }
  return current;
}

void _setDottedValue(Map<String, Object?> doc, String dottedKey, Object? value) {
  final List<String> parts = dottedKey.split('.');
  if (parts.length == 1) {
    doc[dottedKey] = _deepCopyValue(value);
    return;
  }
  Map<String, Object?> current = doc;
  for (int i = 0; i < parts.length - 1; i += 1) {
    final String part = parts[i];
    final Object? existing = current[part];
    if (existing is Map<String, Object?>) {
      current = existing;
    } else if (existing is Map) {
      final Map<String, Object?> converted = _asStringObjectMap(existing);
      current[part] = converted;
      current = converted;
    } else {
      final Map<String, Object?> created = <String, Object?>{};
      current[part] = created;
      current = created;
    }
  }
  current[parts.last] = _deepCopyValue(value);
}

void _applyUpdate(Map<String, Object?> doc, Map<String, Object?> update) {
  final Object? setRaw = update[r'$set'];
  if (setRaw is Map) {
    setRaw.forEach((Object? key, Object? value) {
      _setDottedValue(doc, '$key', value);
    });
  }
  final Object? setOnInsertRaw = update[r'$setOnInsert'];
  if (setOnInsertRaw is Map) {
    setOnInsertRaw.forEach((Object? key, Object? value) {
      final String k = '$key';
      if (_getDottedValue(doc, k) == null) {
        _setDottedValue(doc, k, value);
      }
    });
  }
}

bool _matchesFilter(Map<String, Object?> doc, Map<String, Object?> filter) {
  for (final MapEntry<String, Object?> entry in filter.entries) {
    final String key = entry.key;
    final Object? expected = entry.value;

    if (key == r'$and' && expected is List) {
      for (final Object? clause in expected) {
        if (clause is! Map ||
            !_matchesFilter(doc, _asStringObjectMap(clause))) {
          return false;
        }
      }
      continue;
    }
    if (key == r'$or' && expected is List) {
      final bool anyMatch = expected.any(
        (Object? clause) =>
            clause is Map && _matchesFilter(doc, _asStringObjectMap(clause)),
      );
      if (!anyMatch) {
        return false;
      }
      continue;
    }

    final Object? actual = _getDottedValue(doc, key);
    if (expected is Map &&
        expected.keys.isNotEmpty &&
        expected.keys.every((Object? k) => '$k'.startsWith(r'$'))) {
      for (final MapEntry<Object?, Object?> op in expected.entries) {
        final String opName = '${op.key}';
        final Object? opVal = op.value;
        switch (opName) {
          case r'$eq':
            if (!_matchesScalarOrArrayElement(actual, opVal)) return false;
          case r'$ne':
            if (_matchesScalarOrArrayElement(actual, opVal)) return false;
          case r'$gt':
            if (actual == null || _compareValues(actual, opVal) <= 0) {
              return false;
            }
          case r'$gte':
            if (actual == null || _compareValues(actual, opVal) < 0) {
              return false;
            }
          case r'$lt':
            if (actual == null || _compareValues(actual, opVal) >= 0) {
              return false;
            }
          case r'$lte':
            if (actual == null || _compareValues(actual, opVal) > 0) {
              return false;
            }
          case r'$in':
            if (opVal is! Iterable ||
                !opVal.any(
                  (Object? item) => _matchesScalarOrArrayElement(actual, item),
                )) {
              return false;
            }
          case r'$nin':
            if (opVal is Iterable &&
                opVal.any(
                  (Object? item) => _matchesScalarOrArrayElement(actual, item),
                )) {
              return false;
            }
          case r'$exists':
            final bool exists = actual != null;
            if (exists != (opVal == true)) return false;
        }
      }
    } else if (!_matchesScalarOrArrayElement(actual, expected)) {
      return false;
    }
  }
  return true;
}

bool _matchesScalarOrArrayElement(Object? actual, Object? expected) {
  if (_deepEquals(actual, expected)) {
    return true;
  }
  if (actual is List && expected is! List) {
    return actual.any((Object? element) => _deepEquals(element, expected));
  }
  return false;
}

int _compareValues(Object? a, Object? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return -1;
  }
  if (b == null) {
    return 1;
  }
  if (a is num && b is num) {
    return a.compareTo(b);
  }
  if (a is DateTime && b is DateTime) {
    return a.compareTo(b);
  }
  if (a is DateTime && b is num) {
    return _dateTimeToSeconds(a).compareTo(b.toDouble());
  }
  if (a is num && b is DateTime) {
    return a.toDouble().compareTo(_dateTimeToSeconds(b));
  }
  if (a is String && b is String) {
    return a.compareTo(b);
  }
  return '$a'.compareTo('$b');
}

Map<String, Object?> _applyProjection(
  Map<String, Object?> doc,
  Map<String, Object?> projection,
) {
  final bool hasInclusions = projection.entries.any(
    (MapEntry<String, Object?> entry) =>
        entry.key != '_id' && (entry.value == 1 || entry.value == true),
  );
  if (hasInclusions) {
    final Map<String, Object?> projected = <String, Object?>{};
    final bool includeId =
        projection['_id'] != 0 && projection['_id'] != false;
    if (includeId && doc.containsKey('_id')) {
      projected['_id'] = _deepCopyValue(doc['_id']);
    }
    projection.forEach((String key, Object? value) {
      if ((value == 1 || value == true) && doc.containsKey(key)) {
        projected[key] = _deepCopyValue(doc[key]);
      }
    });
    return projected;
  }

  final Map<String, Object?> projected = _deepCopyMap(doc);
  projection.forEach((String key, Object? value) {
    if (value == 0 || value == false) {
      projected.remove(key);
    }
  });
  return projected;
}

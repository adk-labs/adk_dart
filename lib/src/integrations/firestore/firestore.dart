/// Google Cloud Firestore session and memory service integrations for ADK.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../errors/already_exists_error.dart';
import '../../errors/session_not_found_error.dart';
import '../../errors/stale_session_error.dart';
import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../events/rewind_events.dart';
import '../../events/ui_widget.dart';
import '../../memory/_utils.dart';
import '../../memory/base_memory_service.dart';
import '../../memory/memory_entry.dart';
import '../../platform/time.dart';
import '../../sessions/base_session_service.dart';
import '../../sessions/session.dart';
import '../../sessions/session_util.dart';
import '../../sessions/state.dart';
import '../../types/content.dart';
import '../../types/id.dart';

/// Default root collection name for Firestore session storage.
const String defaultFirestoreRootCollection = 'adk-session';

/// Default sessions subcollection name in Firestore.
const String defaultFirestoreSessionsCollection = 'sessions';

/// Default events subcollection name in Firestore.
const String defaultFirestoreEventsCollection = 'events';

/// Default app-scoped state collection name in Firestore.
const String defaultFirestoreAppStateCollection = 'app_states';

/// Default user-scoped state collection name in Firestore.
const String defaultFirestoreUserStateCollection = 'user_states';

/// Default memories collection name in Firestore.
const String defaultFirestoreMemoriesCollection = 'memories';

const String _staleSessionErrorMessage =
    'The session has been modified in storage since it was loaded. '
    'Please reload the session before appending more events.';

/// Standard English stop words excluded during Firestore memory keyword extraction.
const Set<String> englishStopWords = <String>{
  'a',
  'about',
  'above',
  'after',
  'again',
  'against',
  'all',
  'am',
  'an',
  'and',
  'any',
  'are',
  'as',
  'at',
  'be',
  'because',
  'been',
  'before',
  'being',
  'below',
  'between',
  'both',
  'but',
  'by',
  'can',
  'could',
  'did',
  'do',
  'does',
  'doing',
  'don',
  'down',
  'during',
  'each',
  'else',
  'few',
  'for',
  'from',
  'further',
  'had',
  'has',
  'have',
  'having',
  'he',
  'her',
  'here',
  'hers',
  'herself',
  'him',
  'himself',
  'his',
  'how',
  'i',
  'if',
  'in',
  'into',
  'is',
  'it',
  'its',
  'itself',
  'just',
  'may',
  'me',
  'might',
  'more',
  'most',
  'must',
  'my',
  'myself',
  'no',
  'nor',
  'not',
  'now',
  'of',
  'off',
  'on',
  'once',
  'only',
  'or',
  'other',
  'our',
  'ours',
  'ourselves',
  'out',
  'over',
  'own',
  's',
  'same',
  'shall',
  'she',
  'should',
  'so',
  'some',
  'such',
  't',
  'than',
  'that',
  'the',
  'their',
  'theirs',
  'them',
  'themselves',
  'then',
  'there',
  'these',
  'they',
  'this',
  'those',
  'through',
  'to',
  'too',
  'under',
  'until',
  'up',
  'very',
  'was',
  'we',
  'were',
  'what',
  'when',
  'where',
  'which',
  'who',
  'whom',
  'why',
  'will',
  'with',
  'would',
  'you',
  'your',
  'yours',
  'yourself',
  'yourselves',
};

/// Extracts lowercase alphabetic keywords from [text], filtering out [stopWords].
///
/// Defaults [stopWords] to [englishStopWords].
Set<String> extractKeywords(String text, {Set<String>? stopWords}) {
  final Set<String> activeStopWords = stopWords ?? englishStopWords;
  final RegExp wordPattern = RegExp(r'[A-Za-z]+');
  return wordPattern
      .allMatches(text.toLowerCase())
      .map((RegExpMatch match) => match.group(0)!)
      .where((String word) => !activeStopWords.contains(word))
      .toSet();
}

/// Filter operators supported by [FirestoreFieldFilter].
enum FirestoreFilterOperator {
  /// Equality comparison (`==`).
  equal('=='),

  /// Greater-than-or-equal comparison (`>=`).
  greaterThanOrEqual('>='),

  /// Membership check in an array (`array_contains`).
  arrayContains('array_contains'),

  /// Membership check for any candidate value in an array (`array_contains_any`).
  arrayContainsAny('array_contains_any');

  /// Creates a filter operator with its [wireValue].
  const FirestoreFilterOperator(this.wireValue);

  /// String representation of the operator.
  final String wireValue;
}

/// Single field filter predicate applied to a Firestore collection query.
class FirestoreFieldFilter {
  /// Creates a field filter on [field] using [operator] and [value].
  const FirestoreFieldFilter({
    required this.field,
    required this.operator,
    required this.value,
  });

  /// Document field name to evaluate.
  final String field;

  /// Comparison operator.
  final FirestoreFilterOperator operator;

  /// Target value compared against the document field.
  final Object? value;

  /// Evaluates whether [document] satisfies this filter.
  bool matches(Map<String, Object?> document) {
    final Object? actual = document[field];
    final Object? expected = value;
    switch (operator) {
      case FirestoreFilterOperator.equal:
        return actual == expected;
      case FirestoreFilterOperator.greaterThanOrEqual:
        final double? actualNum = _toEpochSeconds(actual);
        final double? expectedNum = _toEpochSeconds(expected);
        if (actualNum != null && expectedNum != null) {
          return actualNum >= expectedNum;
        }
        if (actual is Comparable && expected is Comparable) {
          try {
            return actual.compareTo(expected) >= 0;
          } catch (_) {
            return false;
          }
        }
        return false;
      case FirestoreFilterOperator.arrayContains:
        if (actual is Iterable) {
          return actual.contains(expected);
        }
        return false;
      case FirestoreFilterOperator.arrayContainsAny:
        if (actual is Iterable && expected is Iterable) {
          final Set<Object?> candidates = expected.toSet();
          return actual.any(candidates.contains);
        }
        return false;
    }
  }
}

/// Snapshot of a single Firestore document.
class FirestoreDocumentSnapshot {
  /// Creates a document snapshot for [path].
  FirestoreDocumentSnapshot({
    required this.path,
    Map<String, Object?>? data,
  }) : _data = data == null ? null : _deepCopyMap(data);

  /// Full slash-delimited document path.
  final String path;

  final Map<String, Object?>? _data;

  /// Document ID (the final segment of [path]).
  String get id => path.split('/').last;

  /// Whether the document exists in Firestore.
  bool get exists => _data != null;

  /// Returns a copy of the document fields, or `null` if the document does not exist.
  Map<String, Object?>? toMap() {
    final Map<String, Object?>? data = _data;
    return data == null ? null : _deepCopyMap(data);
  }
}

/// Injectable client interface for Google Cloud Firestore operations.
///
/// ```dart
/// final client = InMemoryFirestoreDatabaseClient();
/// await client.setDocument('app_states/my_app', {'theme': 'dark'});
/// final doc = await client.getDocument('app_states/my_app');
/// print(doc.toMap()); // {theme: dark}
/// ```
abstract class FirestoreDatabaseClient {
  /// Creates a Firestore database client.
  FirestoreDatabaseClient();

  /// Creates an in-memory [FirestoreDatabaseClient] suitable for local use and testing.
  factory FirestoreDatabaseClient.inMemory() = InMemoryFirestoreDatabaseClient;

  /// Reads a single document at [path].
  Future<FirestoreDocumentSnapshot> getDocument(String path);

  /// Reads multiple documents by their [paths].
  Future<List<FirestoreDocumentSnapshot>> getAllDocuments(List<String> paths) async {
    final List<FirestoreDocumentSnapshot> results = <FirestoreDocumentSnapshot>[];
    for (final String path in paths) {
      results.add(await getDocument(path));
    }
    return results;
  }

  /// Writes [data] to the document at [path], replacing any existing document.
  Future<void> setDocument(String path, Map<String, Object?> data);

  /// Updates [data] fields on an existing document at [path].
  ///
  /// Throws a [StateError] if the document does not exist.
  Future<void> updateDocument(String path, Map<String, Object?> data);

  /// Deletes the document at [path] if it exists.
  Future<void> deleteDocument(String path);

  /// Queries documents directly inside [collectionPath].
  Future<List<FirestoreDocumentSnapshot>> queryCollection(
    String collectionPath, {
    List<FirestoreFieldFilter> filters = const <FirestoreFieldFilter>[],
    String? orderByField,
    bool descending = false,
    int? limitToLast,
  });

  /// Queries documents across all collections named [collectionId].
  Future<List<FirestoreDocumentSnapshot>> queryCollectionGroup(
    String collectionId, {
    List<FirestoreFieldFilter> filters = const <FirestoreFieldFilter>[],
  });

  /// Executes [action] inside an atomic transaction.
  Future<T> runTransaction<T>(
    Future<T> Function(FirestoreDatabaseClient transactionClient) action,
  );
}

/// In-memory implementation of [FirestoreDatabaseClient].
class InMemoryFirestoreDatabaseClient extends FirestoreDatabaseClient {
  /// Creates an empty in-memory Firestore client.
  InMemoryFirestoreDatabaseClient();

  final Map<String, Map<String, Object?>> _documents =
      <String, Map<String, Object?>>{};
  Future<void> _txLock = Future<void>.value();

  static String _normalizePath(String path) {
    final List<String> segments = path
        .split('/')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Firestore path must not be empty.');
    }
    return segments.join('/');
  }

  @override
  Future<FirestoreDocumentSnapshot> getDocument(String path) async {
    final String normalized = _normalizePath(path);
    final Map<String, Object?>? stored = _documents[normalized];
    return FirestoreDocumentSnapshot(path: normalized, data: stored);
  }

  @override
  Future<void> setDocument(String path, Map<String, Object?> data) async {
    final String normalized = _normalizePath(path);
    _documents[normalized] = _deepCopyMap(data);
  }

  @override
  Future<void> updateDocument(String path, Map<String, Object?> data) async {
    final String normalized = _normalizePath(path);
    final Map<String, Object?>? existing = _documents[normalized];
    if (existing == null) {
      throw StateError('Document at $normalized does not exist.');
    }
    final Map<String, Object?> updated = _deepCopyMap(existing);
    updated.addAll(_deepCopyMap(data));
    _documents[normalized] = updated;
  }

  @override
  Future<void> deleteDocument(String path) async {
    final String normalized = _normalizePath(path);
    _documents.remove(normalized);
  }

  @override
  Future<List<FirestoreDocumentSnapshot>> queryCollection(
    String collectionPath, {
    List<FirestoreFieldFilter> filters = const <FirestoreFieldFilter>[],
    String? orderByField,
    bool descending = false,
    int? limitToLast,
  }) async {
    final String normalizedCollection = _normalizePath(collectionPath);
    final List<String> collectionSegments = normalizedCollection.split('/');
    final int expectedDocSegments = collectionSegments.length + 1;
    final String prefix = '$normalizedCollection/';

    List<FirestoreDocumentSnapshot> matches = <FirestoreDocumentSnapshot>[];
    for (final MapEntry<String, Map<String, Object?>> entry
        in _documents.entries) {
      if (!entry.key.startsWith(prefix)) {
        continue;
      }
      final List<String> docSegments = entry.key.split('/');
      if (docSegments.length != expectedDocSegments) {
        continue;
      }
      final Map<String, Object?> data = entry.value;
      final bool passesFilters = filters.every(
        (FirestoreFieldFilter filter) => filter.matches(data),
      );
      if (passesFilters) {
        matches.add(FirestoreDocumentSnapshot(path: entry.key, data: data));
      }
    }

    if (orderByField != null && orderByField.isNotEmpty) {
      matches.sort((FirestoreDocumentSnapshot a, FirestoreDocumentSnapshot b) {
        final Object? va = a.toMap()?[orderByField];
        final Object? vb = b.toMap()?[orderByField];
        final int cmp = _compareFirestoreValues(va, vb);
        return descending ? -cmp : cmp;
      });
    }

    if (limitToLast != null) {
      if (limitToLast <= 0) {
        matches = <FirestoreDocumentSnapshot>[];
      } else if (matches.length > limitToLast) {
        matches = matches.sublist(matches.length - limitToLast);
      }
    }

    return matches;
  }

  @override
  Future<List<FirestoreDocumentSnapshot>> queryCollectionGroup(
    String collectionId, {
    List<FirestoreFieldFilter> filters = const <FirestoreFieldFilter>[],
  }) async {
    final String trimmedId = collectionId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError.value(
        collectionId,
        'collectionId',
        'Collection ID must not be empty.',
      );
    }

    final List<FirestoreDocumentSnapshot> matches =
        <FirestoreDocumentSnapshot>[];
    for (final MapEntry<String, Map<String, Object?>> entry
        in _documents.entries) {
      final List<String> segments = entry.key.split('/');
      if (segments.length < 2) {
        continue;
      }
      final String parentCollection = segments[segments.length - 2];
      if (parentCollection != trimmedId) {
        continue;
      }
      final Map<String, Object?> data = entry.value;
      final bool passesFilters = filters.every(
        (FirestoreFieldFilter filter) => filter.matches(data),
      );
      if (passesFilters) {
        matches.add(FirestoreDocumentSnapshot(path: entry.key, data: data));
      }
    }
    return matches;
  }

  @override
  Future<T> runTransaction<T>(
    Future<T> Function(FirestoreDatabaseClient transactionClient) action,
  ) async {
    final Completer<void> next = Completer<void>();
    final Future<void> previous = _txLock;
    _txLock = next.future;
    try {
      await previous;
      final Map<String, Map<String, Object?>> backup = <String, Map<String, Object?>>{
        for (final MapEntry<String, Map<String, Object?>> entry
            in _documents.entries)
          entry.key: _deepCopyMap(entry.value),
      };
      try {
        return await action(this);
      } catch (_) {
        _documents
          ..clear()
          ..addAll(backup);
        rethrow;
      }
    } finally {
      next.complete();
    }
  }
}

/// Session service backed by Google Cloud Firestore.
///
/// Stores sessions under `<rootCollection>/<appName>/users/<userId>/sessions/<sessionId>`
/// with events in an `events` subcollection, while sharing `app_states` and
/// `user_states` collections across sessions.
///
/// ```dart
/// final service = FirestoreSessionService();
/// final session = await service.createSession(
///   appName: 'my_app',
///   userId: 'user_1',
///   state: {'app:region': 'us', 'user:theme': 'dark', 'step': 1},
/// );
/// ```
class FirestoreSessionService extends BaseSessionService {
  /// Creates a Firestore session service.
  ///
  /// If [client] is omitted, an [InMemoryFirestoreDatabaseClient] is used.
  /// [rootCollection] defaults to `ADK_FIRESTORE_ROOT_COLLECTION` from the
  /// environment or [defaultFirestoreRootCollection].
  FirestoreSessionService({
    FirestoreDatabaseClient? client,
    String? rootCollection,
    this.sessionsCollection = defaultFirestoreSessionsCollection,
    this.eventsCollection = defaultFirestoreEventsCollection,
    this.appStateCollection = defaultFirestoreAppStateCollection,
    this.userStateCollection = defaultFirestoreUserStateCollection,
  }) : client = client ?? InMemoryFirestoreDatabaseClient(),
       rootCollection =
           rootCollection ??
           _nonEmptyEnv('ADK_FIRESTORE_ROOT_COLLECTION') ??
           defaultFirestoreRootCollection;

  /// Underlying Firestore database client.
  final FirestoreDatabaseClient client;

  /// Root collection name for session hierarchies.
  final String rootCollection;

  /// Subcollection name for sessions under each user document.
  final String sessionsCollection;

  /// Subcollection name for events under each session document.
  final String eventsCollection;

  /// Collection name for application-scoped states.
  final String appStateCollection;

  /// Collection name for user-scoped states.
  final String userStateCollection;

  final Map<(String, String, String), Future<void>> _sessionLocks =
      <(String, String, String), Future<void>>{};

  String _sessionsCollectionPath(String appName, String userId) =>
      '$rootCollection/$appName/users/$userId/$sessionsCollection';

  String _sessionDocPath(String appName, String userId, String sessionId) =>
      '${_sessionsCollectionPath(appName, userId)}/$sessionId';

  String _eventsCollectionPath(
    String appName,
    String userId,
    String sessionId,
  ) => '${_sessionDocPath(appName, userId, sessionId)}/$eventsCollection';

  String _appStateDocPath(String appName) => '$appStateCollection/$appName';

  String _userStateDocPath(String appName, String userId) =>
      '$userStateCollection/$appName/users/$userId';

  Future<T> _withSessionLock<T>({
    required String appName,
    required String userId,
    required String sessionId,
    required Future<T> Function() action,
  }) async {
    final (String, String, String) key = (appName, userId, sessionId);
    final Completer<void> completer = Completer<void>();
    final Future<void> previous = _sessionLocks[key] ?? Future<void>.value();
    final Future<void> current = previous.whenComplete(() => completer.future);
    _sessionLocks[key] = current;
    try {
      await previous;
      return await action();
    } finally {
      completer.complete();
      if (identical(_sessionLocks[key], current)) {
        _sessionLocks.remove(key);
      }
    }
  }

  static Map<String, Object?> _mergeState({
    Map<String, Object?>? appState,
    Map<String, Object?>? userState,
    required Map<String, Object?> sessionState,
  }) {
    final Map<String, Object?> merged = _deepCopyMap(sessionState);
    if (appState != null) {
      appState.forEach((String key, Object? value) {
        merged['${State.appPrefix}$key'] = value;
      });
    }
    if (userState != null) {
      userState.forEach((String key, Object? value) {
        merged['${State.userPrefix}$key'] = value;
      });
    }
    return merged;
  }

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    final String resolvedSessionId =
        (sessionId != null && sessionId.trim().isNotEmpty)
        ? sessionId.trim()
        : newAdkId(prefix: 'session_');

    final Map<String, Object?> initialState = state ?? <String, Object?>{};
    final SessionStateDelta deltas = extractStateDelta(initialState);
    final Map<String, Object?> appStateDelta = deltas.app;
    final Map<String, Object?> userStateDelta = deltas.user;
    final Map<String, Object?> sessionState = _makeJsonSafeMap(deltas.session);

    final String sessionPath = _sessionDocPath(
      appName,
      userId,
      resolvedSessionId,
    );
    final String appPath = _appStateDocPath(appName);
    final String userPath = _userStateDocPath(appName, userId);
    final double now = getTime();

    final Map<String, Object?> sessionData = <String, Object?>{
      'id': resolvedSessionId,
      'appName': appName,
      'userId': userId,
      'state': jsonEncode(sessionState),
      'createTime': now,
      'updateTime': now,
      'revision': 0,
    };

    final (
      Map<String, Object?> storageAppState,
      Map<String, Object?> storageUserState,
    ) = await client.runTransaction<(Map<String, Object?>, Map<String, Object?>)>((
      FirestoreDatabaseClient txn,
    ) async {
      final FirestoreDocumentSnapshot snap = await txn.getDocument(sessionPath);
      if (snap.exists) {
        throw AlreadyExistsError('Session $resolvedSessionId already exists.');
      }

      final FirestoreDocumentSnapshot appSnap = await txn.getDocument(appPath);
      final FirestoreDocumentSnapshot userSnap = await txn.getDocument(userPath);

      final Map<String, Object?> currentApp =
          appSnap.toMap() ?? <String, Object?>{};
      final Map<String, Object?> currentUser =
          userSnap.toMap() ?? <String, Object?>{};

      if (appStateDelta.isNotEmpty) {
        currentApp.addAll(appStateDelta);
        await txn.setDocument(appPath, currentApp);
      }
      if (userStateDelta.isNotEmpty) {
        currentUser.addAll(userStateDelta);
        await txn.setDocument(userPath, currentUser);
      }

      await txn.setDocument(sessionPath, sessionData);
      return (currentApp, currentUser);
    });

    final Map<String, Object?> mergedState = _mergeState(
      appState: storageAppState,
      userState: storageUserState,
      sessionState: sessionState,
    );

    return Session(
      id: resolvedSessionId,
      appName: appName,
      userId: userId,
      state: mergedState,
      events: <Event>[],
      lastUpdateTime: now,
      storageUpdateMarker: '0',
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    final String sessionPath = _sessionDocPath(appName, userId, sessionId);
    final FirestoreDocumentSnapshot doc = await client.getDocument(sessionPath);
    if (!doc.exists) {
      return null;
    }
    final Map<String, Object?>? data = doc.toMap();
    if (data == null || data.isEmpty) {
      return null;
    }

    final String appPath = _appStateDocPath(appName);
    final String userPath = _userStateDocPath(appName, userId);

    List<FirestoreDocumentSnapshot> eventDocs;
    FirestoreDocumentSnapshot appDoc;
    FirestoreDocumentSnapshot userDoc;

    if (config != null && config.numRecentEvents == 0) {
      eventDocs = const <FirestoreDocumentSnapshot>[];
      final List<FirestoreDocumentSnapshot> stateDocs = await Future.wait(
        <Future<FirestoreDocumentSnapshot>>[
          client.getDocument(appPath),
          client.getDocument(userPath),
        ],
      );
      appDoc = stateDocs[0];
      userDoc = stateDocs[1];
    } else {
      final List<FirestoreFieldFilter> filters = <FirestoreFieldFilter>[];
      if (config?.afterTimestamp != null) {
        filters.add(
          FirestoreFieldFilter(
            field: 'timestamp',
            operator: FirestoreFilterOperator.greaterThanOrEqual,
            value: config!.afterTimestamp,
          ),
        );
      }

      final Future<List<FirestoreDocumentSnapshot>> eventsFuture = client
          .queryCollection(
            _eventsCollectionPath(appName, userId, sessionId),
            filters: filters,
            orderByField: 'timestamp',
            limitToLast: config?.numRecentEvents,
          );
      final Future<FirestoreDocumentSnapshot> appFuture = client.getDocument(
        appPath,
      );
      final Future<FirestoreDocumentSnapshot> userFuture = client.getDocument(
        userPath,
      );

      eventDocs = await eventsFuture;
      appDoc = await appFuture;
      userDoc = await userFuture;
    }

    final List<Event> events = <Event>[];
    for (final FirestoreDocumentSnapshot eventDoc in eventDocs) {
      final Map<String, Object?>? eventData = eventDoc.toMap();
      if (eventData != null && eventData['event_data'] is Map) {
        events.add(
          _firestoreEventFromJson(_castStringObjectMap(eventData['event_data'])),
        );
      }
    }

    final Map<String, Object?> sessionState = _decodeSessionState(data['state']);
    final Map<String, Object?> appState = appDoc.toMap() ?? <String, Object?>{};
    final Map<String, Object?> userState =
        userDoc.toMap() ?? <String, Object?>{};

    final Map<String, Object?> mergedState = _mergeState(
      appState: appState,
      userState: userState,
      sessionState: sessionState,
    );

    final int currentRevision = _asInt(data['revision']) ?? 0;
    return Session(
      id: sessionId,
      appName: appName,
      userId: userId,
      state: mergedState,
      events: events,
      lastUpdateTime: _toEpochSeconds(data['updateTime']) ?? 0.0,
      storageUpdateMarker: '$currentRevision',
    );
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    if (userId == '') {
      return ListSessionsResponse(sessions: <Session>[]);
    }
    final List<FirestoreDocumentSnapshot> docs;
    if (userId != null) {
      docs = await client.queryCollection(
        _sessionsCollectionPath(appName, userId),
        filters: <FirestoreFieldFilter>[
          FirestoreFieldFilter(
            field: 'appName',
            operator: FirestoreFilterOperator.equal,
            value: appName,
          ),
        ],
      );
    } else {
      docs = await client.queryCollectionGroup(
        sessionsCollection,
        filters: <FirestoreFieldFilter>[
          FirestoreFieldFilter(
            field: 'appName',
            operator: FirestoreFilterOperator.equal,
            value: appName,
          ),
        ],
      );
    }

    final List<Map<String, Object?>> sessionDataList = docs
        .map((FirestoreDocumentSnapshot doc) => doc.toMap())
        .whereType<Map<String, Object?>>()
        .where((Map<String, Object?> data) => data.isNotEmpty)
        .toList(growable: false);

    final FirestoreDocumentSnapshot appDoc = await client.getDocument(
      _appStateDocPath(appName),
    );
    final Map<String, Object?> appState = appDoc.toMap() ?? <String, Object?>{};

    final Map<String, Map<String, Object?>> userStatesMap =
        <String, Map<String, Object?>>{};
    if (userId != null && userId.isNotEmpty) {
      final FirestoreDocumentSnapshot userDoc = await client.getDocument(
        _userStateDocPath(appName, userId),
      );
      if (userDoc.exists) {
        userStatesMap[userId] = userDoc.toMap() ?? <String, Object?>{};
      }
    } else {
      final List<String> uniqueUserIds =
          sessionDataList
              .map((Map<String, Object?> s) => s['userId'])
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();
      if (uniqueUserIds.isNotEmpty) {
        final List<String> userPaths = uniqueUserIds
            .map((String uid) => _userStateDocPath(appName, uid))
            .toList(growable: false);
        final List<FirestoreDocumentSnapshot> userDocs = await client
            .getAllDocuments(userPaths);
        for (final FirestoreDocumentSnapshot uDoc in userDocs) {
          if (uDoc.exists) {
            userStatesMap[uDoc.id] = uDoc.toMap() ?? <String, Object?>{};
          }
        }
      }
    }

    final List<Session> sessions = <Session>[];
    for (final Map<String, Object?> data in sessionDataList) {
      final String uId = '${data['userId'] ?? ''}';
      final Map<String, Object?> sState = _decodeSessionState(data['state']);
      final Map<String, Object?> uState =
          userStatesMap[uId] ?? <String, Object?>{};
      final Map<String, Object?> merged = _mergeState(
        appState: appState,
        userState: uState,
        sessionState: sState,
      );

      sessions.add(
        Session(
          id: '${data['id'] ?? ''}',
          appName: '${data['appName'] ?? appName}',
          userId: uId,
          state: merged,
          events: <Event>[],
          lastUpdateTime: _toEpochSeconds(data['updateTime']) ?? 0.0,
        ),
      );
    }

    sessions.sort((Session a, Session b) {
      final int timeCmp = a.lastUpdateTime.compareTo(b.lastUpdateTime);
      if (timeCmp != 0) {
        return timeCmp;
      }
      final int userCmp = a.userId.compareTo(b.userId);
      if (userCmp != 0) {
        return userCmp;
      }
      return a.id.compareTo(b.id);
    });

    return ListSessionsResponse(sessions: sessions);
  }

  @override
  Future<Map<String, Object?>> getUserState({
    required String appName,
    required String userId,
  }) async {
    final FirestoreDocumentSnapshot userDoc = await client.getDocument(
      _userStateDocPath(appName, userId),
    );
    if (!userDoc.exists) {
      return <String, Object?>{};
    }
    return userDoc.toMap() ?? <String, Object?>{};
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    final String sessionPath = _sessionDocPath(appName, userId, sessionId);
    try {
      await client.runTransaction<void>((FirestoreDatabaseClient txn) async {
        final FirestoreDocumentSnapshot snap = await txn.getDocument(
          sessionPath,
        );
        if (snap.exists) {
          await txn.updateDocument(sessionPath, <String, Object?>{
            'status': 'DELETING',
          });
        }
      });
    } catch (_) {
      // Best-effort status marker update before deleting event documents.
    }

    final List<FirestoreDocumentSnapshot> eventDocs = await client
        .queryCollection(_eventsCollectionPath(appName, userId, sessionId));
    for (final FirestoreDocumentSnapshot eventDoc in eventDocs) {
      await client.deleteDocument(eventDoc.path);
    }
    await client.deleteDocument(sessionPath);
  }

  @override
  Future<Event> appendEvent({
    required Session session,
    required Event event,
  }) async {
    if (event.partial == true) {
      return event;
    }

    // Apply temp: keys to live session state, then strip temp: keys from persistence.
    if (event.actions.stateDelta.isNotEmpty) {
      event.actions.stateDelta.forEach((String key, Object? value) {
        if (key.startsWith(State.tempPrefix)) {
          session.state[key] = value;
        }
      });
    }
    final Event trimmedEvent = eventForPersistence(event);

    final String sessionPath = _sessionDocPath(
      session.appName,
      session.userId,
      session.id,
    );
    final SessionStateDelta stateDeltas = extractStateDelta(
      trimmedEvent.actions.stateDelta,
    );
    final Map<String, Object?> appUpdates = stateDeltas.app;
    final Map<String, Object?> userUpdates = stateDeltas.user;
    final Map<String, Object?> sessionUpdates = stateDeltas.session;

    final String appPath = _appStateDocPath(session.appName);
    final String userPath = _userStateDocPath(session.appName, session.userId);

    await _withSessionLock<void>(
      appName: session.appName,
      userId: session.userId,
      sessionId: session.id,
      action: () async {
        final int newRevisionCount = await client.runTransaction<int>((
          FirestoreDatabaseClient txn,
        ) async {
          final FirestoreDocumentSnapshot sessionSnap = await txn.getDocument(
            sessionPath,
          );
          if (!sessionSnap.exists) {
            throw SessionNotFoundError('Session ${session.id} not found.');
          }

          final Map<String, Object?> sessionDoc =
              sessionSnap.toMap() ?? <String, Object?>{};
          if (sessionDoc['status'] == 'DELETING') {
            throw StateError(
              'Session ${session.id} is currently being deleted.',
            );
          }

          final int currentRevision = _asInt(sessionDoc['revision']) ?? 0;
          if (session.storageUpdateMarker != null &&
              session.storageUpdateMarker != '$currentRevision') {
            throw StaleSessionError(_staleSessionErrorMessage);
          }

          final FirestoreDocumentSnapshot? appSnap = appUpdates.isNotEmpty
              ? await txn.getDocument(appPath)
              : null;
          final FirestoreDocumentSnapshot? userSnap = userUpdates.isNotEmpty
              ? await txn.getDocument(userPath)
              : null;

          if (appUpdates.isNotEmpty && appSnap != null) {
            final Map<String, Object?> currentApp =
                appSnap.toMap() ?? <String, Object?>{};
            currentApp.addAll(appUpdates);
            await txn.setDocument(appPath, currentApp);
          }

          if (userUpdates.isNotEmpty && userSnap != null) {
            final Map<String, Object?> currentUser =
                userSnap.toMap() ?? <String, Object?>{};
            currentUser.addAll(userUpdates);
            await txn.setDocument(userPath, currentUser);
          }

          final int nextRevision = currentRevision + 1;
          final Map<String, Object?> sessionOnlyState = <String, Object?>{
            for (final MapEntry<String, Object?> entry in session.state.entries)
              if (!entry.key.startsWith(State.appPrefix) &&
                  !entry.key.startsWith(State.userPrefix) &&
                  !entry.key.startsWith(State.tempPrefix))
                entry.key: entry.value,
          };
          sessionOnlyState.addAll(sessionUpdates);
          final Map<String, Object?> safeSessionState = _makeJsonSafeMap(
            sessionOnlyState,
          );

          await txn.updateDocument(sessionPath, <String, Object?>{
            'state': jsonEncode(safeSessionState),
            'updateTime': trimmedEvent.timestamp,
            'revision': nextRevision,
          });

          final String eventPath =
              '${_eventsCollectionPath(session.appName, session.userId, session.id)}/${trimmedEvent.id}';
          await txn.setDocument(eventPath, <String, Object?>{
            'event_data': _firestoreEventToJson(trimmedEvent),
            'timestamp': trimmedEvent.timestamp,
            'appName': session.appName,
            'userId': session.userId,
          });

          return nextRevision;
        });

        session.storageUpdateMarker = '$newRevisionCount';
        session.lastUpdateTime = trimmedEvent.timestamp;
      },
    );

    return commitEventToSession(session: session, event: trimmedEvent);
  }
}

/// Memory service backed by Google Cloud Firestore.
///
/// Indexes session events and memories with extracted keywords into a top-level
/// Firestore collection and supports keyword-based memory search.
///
/// ```dart
/// final memoryService = FirestoreMemoryService();
/// await memoryService.addSessionToMemory(session);
/// final results = await memoryService.searchMemory(
///   appName: 'my_app',
///   userId: 'user_1',
///   query: 'flight booking confirmation',
/// );
/// ```
class FirestoreMemoryService extends BaseMemoryService {
  /// Creates a Firestore memory service.
  FirestoreMemoryService({
    FirestoreDatabaseClient? client,
    String? eventsCollection,
    Set<String>? stopWords,
    String? memoriesCollection,
  }) : client = client ?? InMemoryFirestoreDatabaseClient(),
       eventsCollection = eventsCollection ?? defaultFirestoreEventsCollection,
       memoriesCollection =
           memoriesCollection ?? defaultFirestoreMemoriesCollection,
       stopWords = stopWords ?? englishStopWords;

  /// Underlying Firestore database client.
  final FirestoreDatabaseClient client;

  /// Name of the events collection or collection group.
  final String eventsCollection;

  /// Name of the top-level memories collection.
  final String memoriesCollection;

  /// Words ignored when extracting search keywords.
  final Set<String> stopWords;

  static String _memoryDocId({
    required String appName,
    required String userId,
    required String? sessionId,
    required String eventId,
  }) {
    final String key = <String>[
      appName,
      userId,
      sessionId ?? '',
      eventId,
    ].join('\x00');
    return sha256.convert(utf8.encode(key)).toString();
  }

  @override
  Future<void> addSessionToMemory(
    Session session, {
    Map<String, Object?>? customMetadata,
  }) async {
    final List<Event> activeEvents = applyRewinds(session.events);
    final Set<String> activeIds = activeEvents
        .map((Event e) => e.id)
        .where((String id) => id.isNotEmpty)
        .toSet();
    for (final Event event in session.events) {
      if (event.id.isEmpty || activeIds.contains(event.id)) {
        continue;
      }
      final String docId = _memoryDocId(
        appName: session.appName,
        userId: session.userId,
        sessionId: session.id,
        eventId: event.id,
      );
      await client.deleteDocument('$memoriesCollection/$docId');
    }
    await _writeMemories(
      appName: session.appName,
      userId: session.userId,
      sessionId: session.id,
      events: activeEvents,
    );
  }

  @override
  Future<void> addEventsToMemory({
    required String appName,
    required String userId,
    required List<Event> events,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    await _writeMemories(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      events: events,
    );
  }

  @override
  Future<void> addMemory({
    required String appName,
    required String userId,
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) async {
    int index = 0;
    for (final MemoryEntry memory in memories) {
      index += 1;
      final Content content = memory.content;
      if (content.parts.isEmpty) {
        continue;
      }
      final String text = content.parts
          .where((Part part) => part.text != null && part.text!.isNotEmpty)
          .map((Part part) => part.text!)
          .join(' ');
      if (text.isEmpty) {
        continue;
      }
      final Set<String> keywords = extractKeywords(text, stopWords: stopWords);
      if (keywords.isEmpty) {
        continue;
      }
      final String entryId =
          (memory.id != null && memory.id!.isNotEmpty)
          ? memory.id!
          : 'mem_${index}_${text.hashCode}';
      final String docId = _memoryDocId(
        appName: appName,
        userId: userId,
        sessionId: null,
        eventId: entryId,
      );
      final double timestamp = _parseMemoryTimestamp(memory.timestamp);
      await client.setDocument('$memoriesCollection/$docId', <String, Object?>{
        'appName': appName,
        'userId': userId,
        'sessionId': null,
        'keywords': keywords.toList(growable: false),
        'author': memory.author ?? '',
        'content': _firestoreContentToJson(content),
        'timestamp': timestamp,
      });
    }
  }

  Future<void> _writeMemories({
    required String appName,
    required String userId,
    required String? sessionId,
    required List<Event> events,
  }) async {
    final Set<String> seenEventIds = <String>{};
    for (final Event event in events) {
      if (!seenEventIds.add(event.id)) {
        continue;
      }
      final Content? content = event.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }
      final String text = content.parts
          .where((Part part) => part.text != null && part.text!.isNotEmpty)
          .map((Part part) => part.text!)
          .join(' ');
      if (text.isEmpty) {
        continue;
      }
      final Set<String> keywords = extractKeywords(text, stopWords: stopWords);
      if (keywords.isEmpty) {
        continue;
      }
      final String docId = _memoryDocId(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        eventId: event.id,
      );
      await client.setDocument('$memoriesCollection/$docId', <String, Object?>{
        'appName': appName,
        'userId': userId,
        'sessionId': sessionId,
        'keywords': keywords.toList(growable: false),
        'author': event.author,
        'content': _firestoreContentToJson(content),
        'timestamp': event.timestamp,
      });
    }
  }

  Future<List<MemoryEntry>> _searchByKeyword(
    String appName,
    String userId,
    String keyword,
  ) async {
    final List<FirestoreDocumentSnapshot> docs = await client.queryCollection(
      memoriesCollection,
      filters: <FirestoreFieldFilter>[
        FirestoreFieldFilter(
          field: 'appName',
          operator: FirestoreFilterOperator.equal,
          value: appName,
        ),
        FirestoreFieldFilter(
          field: 'userId',
          operator: FirestoreFilterOperator.equal,
          value: userId,
        ),
        FirestoreFieldFilter(
          field: 'keywords',
          operator: FirestoreFilterOperator.arrayContains,
          value: keyword,
        ),
      ],
    );

    final List<MemoryEntry> entries = <MemoryEntry>[];
    for (final FirestoreDocumentSnapshot doc in docs) {
      final Map<String, Object?>? data = doc.toMap();
      if (data != null && data['content'] is Map) {
        try {
          final Content content = _firestoreContentFromJson(
            _castStringObjectMap(data['content']),
          );
          final double ts = _toEpochSeconds(data['timestamp']) ?? 0.0;
          entries.add(
            MemoryEntry(
              content: content,
              author: '${data['author'] ?? ''}',
              timestamp: formatTimestamp(ts),
            ),
          );
        } catch (_) {
          // Skip malformed memory entries.
        }
      }
    }
    return entries;
  }

  @override
  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  }) async {
    final Set<String> keywords = extractKeywords(query, stopWords: stopWords);
    if (keywords.isEmpty) {
      return SearchMemoryResponse();
    }

    final List<List<MemoryEntry>> resultLists = await Future.wait(
      keywords.map((String keyword) async {
        try {
          return await _searchByKeyword(appName, userId, keyword);
        } catch (_) {
          return const <MemoryEntry>[];
        }
      }),
    );

    final Set<(String?, String, String?)> seen = <(String?, String, String?)>{};
    final List<MemoryEntry> memories = <MemoryEntry>[];
    for (final List<MemoryEntry> list in resultLists) {
      for (final MemoryEntry entry in list) {
        final String contentText = entry.content.parts
            .where((Part p) => p.text != null && p.text!.isNotEmpty)
            .map((Part p) => p.text!)
            .join(' ');
        final (String?, String, String?) key = (
          entry.author,
          contentText,
          entry.timestamp,
        );
        if (seen.add(key)) {
          memories.add(entry);
        }
      }
    }

    return SearchMemoryResponse(memories: memories);
  }
}

String? _nonEmptyEnv(String name) {
  final String? value = Platform.environment[name]?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

double? _toEpochSeconds(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is DateTime) {
    return value.toUtc().millisecondsSinceEpoch / 1000.0;
  }
  if (value is String) {
    final double? parsed = double.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
    final DateTime? dt = DateTime.tryParse(value);
    if (dt != null) {
      return dt.toUtc().millisecondsSinceEpoch / 1000.0;
    }
  }
  return null;
}

double _parseMemoryTimestamp(String? timestamp) {
  if (timestamp == null || timestamp.isEmpty) {
    return 0.0;
  }
  return _toEpochSeconds(timestamp) ?? 0.0;
}

int _compareFirestoreValues(Object? a, Object? b) {
  final double? na = _toEpochSeconds(a);
  final double? nb = _toEpochSeconds(b);
  if (na != null && nb != null) {
    return na.compareTo(nb);
  }
  if (a is Comparable && b is Comparable) {
    try {
      return a.compareTo(b);
    } catch (_) {
      return '$a'.compareTo('$b');
    }
  }
  return '$a'.compareTo('$b');
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

Map<String, Object?> _decodeSessionState(Object? rawState) {
  if (rawState is Map) {
    return _castStringObjectMap(rawState);
  }
  if (rawState is String && rawState.trim().isNotEmpty) {
    try {
      final Object? decoded = jsonDecode(rawState);
      if (decoded is Map) {
        return _castStringObjectMap(decoded);
      }
    } catch (_) {
      return <String, Object?>{};
    }
  }
  return <String, Object?>{};
}

Map<String, Object?> _makeJsonSafeMap(Map<String, Object?> state) {
  final Map<String, Object?> result = <String, Object?>{};
  state.forEach((String key, Object? value) {
    result[key] = _makeJsonSafeValue(value);
  });
  return result;
}

Object? _makeJsonSafeValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is List) {
    return value.map(_makeJsonSafeValue).toList();
  }
  if (value is Set) {
    return value.map(_makeJsonSafeValue).toList();
  }
  if (value is Map) {
    return value.map(
      (Object? k, Object? v) => MapEntry('$k', _makeJsonSafeValue(v)),
    );
  }
  try {
    jsonEncode(value);
    return value;
  } catch (_) {
    return '$value';
  }
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> source) {
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in source.entries)
      entry.key: _deepCopyValue(entry.value),
  };
}

Object? _deepCopyValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': _deepCopyValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_deepCopyValue).toList();
  }
  return value;
}

Map<String, Object?> _castStringObjectMap(Object? value) {
  if (value is Map) {
    return value.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  return <String, Object?>{};
}

Map<String, Object?> _firestoreEventToJson(Event event) {
  return <String, Object?>{
    'invocationId': event.invocationId,
    'author': event.author,
    'id': event.id,
    'timestamp': event.timestamp,
    'actions': _firestoreEventActionsToJson(event.actions),
    if (!event.nodeInfo.isEmpty)
      'nodeInfo': eventNodeInfoToJson(event.nodeInfo),
    if (event.hasOutput) 'output': event.output,
    if (event.longRunningToolIds != null)
      'longRunningToolIds': event.longRunningToolIds!.toList(),
    if (event.branch != null) 'branch': event.branch,
    if (event.isolationScope != null) 'isolationScope': event.isolationScope,
    if (event.modelVersion != null) 'modelVersion': event.modelVersion,
    if (event.content != null)
      'content': _firestoreContentToJson(event.content!),
    if (event.partial != null) 'partial': event.partial,
    if (event.turnComplete != null) 'turnComplete': event.turnComplete,
    if (event.finishReason != null) 'finishReason': event.finishReason,
    if (event.errorCode != null) 'errorCode': event.errorCode,
    if (event.errorMessage != null) 'errorMessage': event.errorMessage,
    if (event.interrupted != null) 'interrupted': event.interrupted,
    if (event.customMetadata != null) 'customMetadata': event.customMetadata,
    if (event.usageMetadata != null) 'usageMetadata': event.usageMetadata,
    if (event.inputTranscription != null)
      'inputTranscription': event.inputTranscription,
    if (event.outputTranscription != null)
      'outputTranscription': event.outputTranscription,
    if (event.avgLogprobs != null) 'avgLogprobs': event.avgLogprobs,
    if (event.logprobsResult != null) 'logprobsResult': event.logprobsResult,
    if (event.cacheMetadata != null) 'cacheMetadata': event.cacheMetadata,
    if (event.citationMetadata != null)
      'citationMetadata': event.citationMetadata,
    if (event.groundingMetadata != null)
      'groundingMetadata': event.groundingMetadata,
    if (event.interactionId != null) 'interactionId': event.interactionId,
    if (event.environmentId != null) 'environmentId': event.environmentId,
    if (event.liveSessionId != null) 'liveSessionId': event.liveSessionId,
    if (event.liveSessionResumptionUpdate != null)
      'liveSessionResumptionUpdate': event.liveSessionResumptionUpdate,
    if (event.goAway != null) 'goAway': event.goAway,
  };
}

Event _firestoreEventFromJson(Map<String, Object?> json) {
  final Event event = Event(
    invocationId: '${json['invocationId'] ?? json['invocation_id'] ?? ''}',
    author: '${json['author'] ?? ''}',
    id: '${json['id'] ?? ''}',
    timestamp: _toEpochSeconds(json['timestamp']) ?? 0.0,
    actions: _firestoreEventActionsFromJson(
      _castStringObjectMap(json['actions']),
    ),
    nodeInfo: eventNodeInfoFromJson(
      _castStringObjectMap(json['nodeInfo'] ?? json['node_info']),
    ),
    longRunningToolIds: (json['longRunningToolIds'] is List)
        ? (json['longRunningToolIds'] as List).whereType<String>().toSet()
        : null,
    branch: json['branch'] as String?,
    isolationScope:
        (json['isolationScope'] ?? json['isolation_scope']) as String?,
    modelVersion: (json['modelVersion'] ?? json['model_version']) as String?,
    content: json['content'] is Map
        ? _firestoreContentFromJson(_castStringObjectMap(json['content']))
        : null,
    partial: json['partial'] as bool?,
    turnComplete: (json['turnComplete'] ?? json['turn_complete']) as bool?,
    finishReason: (json['finishReason'] ?? json['finish_reason']) as String?,
    errorCode: (json['errorCode'] ?? json['error_code']) as String?,
    errorMessage: (json['errorMessage'] ?? json['error_message']) as String?,
    interrupted: json['interrupted'] as bool?,
    customMetadata: json['customMetadata'] is Map
        ? (json['customMetadata'] as Map).map(
            (Object? k, Object? v) => MapEntry('$k', v),
          )
        : null,
    usageMetadata: json['usageMetadata'],
    inputTranscription: json['inputTranscription'],
    outputTranscription: json['outputTranscription'],
    avgLogprobs: (json['avgLogprobs'] is num)
        ? (json['avgLogprobs'] as num).toDouble()
        : null,
    logprobsResult: json['logprobsResult'],
    cacheMetadata: json['cacheMetadata'],
    citationMetadata: json['citationMetadata'],
    groundingMetadata: json['groundingMetadata'],
    interactionId: json['interactionId'] as String?,
    environmentId: json['environmentId'] as String?,
    liveSessionId: json['liveSessionId'] as String?,
    liveSessionResumptionUpdate: json['liveSessionResumptionUpdate'],
    goAway: json['goAway'],
  );
  if (json.containsKey('output')) {
    event.output = json['output'];
    event.hasOutput = true;
  }
  return event;
}

Map<String, Object?> _firestoreEventActionsToJson(EventActions actions) {
  return <String, Object?>{
    if (actions.skipSummarization != null)
      'skipSummarization': actions.skipSummarization,
    'stateDelta': actions.stateDelta,
    'artifactDelta': actions.artifactDelta,
    if (actions.transferToAgent != null)
      'transferToAgent': actions.transferToAgent,
    if (actions.escalate != null) 'escalate': actions.escalate,
    if (actions.requestedAuthConfigs.isNotEmpty)
      'requestedAuthConfigs': actions.requestedAuthConfigs,
    if (actions.requestedToolConfirmations.isNotEmpty)
      'requestedToolConfirmations': actions.requestedToolConfirmations,
    if (actions.renderUiWidgets.isNotEmpty)
      'renderUiWidgets': actions.renderUiWidgets
          .map((UiWidget widget) => widget.toJson())
          .toList(growable: false),
    if (actions.compaction != null)
      'compaction': <String, Object?>{
        'startTimestamp': actions.compaction!.startTimestamp,
        'endTimestamp': actions.compaction!.endTimestamp,
        'compactedContent': _firestoreContentToJson(
          actions.compaction!.compactedContent,
        ),
      },
    if (actions.endOfAgent != null) 'endOfAgent': actions.endOfAgent,
    if (actions.agentState != null) 'agentState': actions.agentState,
    if (actions.rewindBeforeInvocationId != null)
      'rewindBeforeInvocationId': actions.rewindBeforeInvocationId,
    if (actions.route != null) 'route': actions.route,
  };
}

EventActions _firestoreEventActionsFromJson(Map<String, Object?> json) {
  EventCompaction? compaction;
  if (json['compaction'] is Map) {
    final Map<String, Object?> compactionMap = _castStringObjectMap(
      json['compaction'],
    );
    compaction = EventCompaction(
      startTimestamp: _toEpochSeconds(compactionMap['startTimestamp']) ?? 0.0,
      endTimestamp: _toEpochSeconds(compactionMap['endTimestamp']) ?? 0.0,
      compactedContent: _firestoreContentFromJson(
        _castStringObjectMap(compactionMap['compactedContent']),
      ),
    );
  }
  final Map<String, int> artifactDelta = <String, int>{};
  final Object? rawArtifactDelta =
      json['artifactDelta'] ?? json['artifact_delta'];
  if (rawArtifactDelta is Map) {
    rawArtifactDelta.forEach((Object? k, Object? v) {
      if (v is num) {
        artifactDelta['$k'] = v.toInt();
      }
    });
  }
  final Map<String, Object> requestedAuthConfigs = <String, Object>{};
  if (json['requestedAuthConfigs'] is Map) {
    (json['requestedAuthConfigs'] as Map).forEach((Object? k, Object? v) {
      if (v != null) {
        requestedAuthConfigs['$k'] = v;
      }
    });
  }
  final Map<String, Object> requestedToolConfirmations = <String, Object>{};
  if (json['requestedToolConfirmations'] is Map) {
    (json['requestedToolConfirmations'] as Map).forEach((Object? k, Object? v) {
      if (v != null) {
        requestedToolConfirmations['$k'] = v;
      }
    });
  }
  final List<UiWidget> widgets = <UiWidget>[];
  if (json['renderUiWidgets'] is List) {
    for (final Object? item in json['renderUiWidgets'] as List) {
      if (item is Map) {
        widgets.add(UiWidget.fromJson(_castStringObjectMap(item)));
      }
    }
  }
  return EventActions(
    skipSummarization:
        (json['skipSummarization'] ?? json['skip_summarization']) as bool?,
    stateDelta: _castStringObjectMap(json['stateDelta'] ?? json['state_delta']),
    artifactDelta: artifactDelta,
    transferToAgent:
        (json['transferToAgent'] ?? json['transfer_to_agent']) as String?,
    escalate: json['escalate'] as bool?,
    requestedAuthConfigs: requestedAuthConfigs,
    requestedToolConfirmations: requestedToolConfirmations,
    renderUiWidgets: widgets,
    compaction: compaction,
    endOfAgent: (json['endOfAgent'] ?? json['end_of_agent']) as bool?,
    agentState: json['agentState'] is Map
        ? _castStringObjectMap(json['agentState'])
        : null,
    rewindBeforeInvocationId:
        (json['rewindBeforeInvocationId'] ?? json['rewind_before_invocation_id'])
            as String?,
    route: json['route'],
  );
}

Map<String, Object?> _firestoreContentToJson(Content content) {
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map(_firestorePartToJson).toList(),
  };
}

Content _firestoreContentFromJson(Map<String, Object?> json) {
  final List<Part> parts = <Part>[];
  if (json['parts'] is List) {
    for (final Object? item in json['parts'] as List) {
      if (item is Map) {
        parts.add(_firestorePartFromJson(_castStringObjectMap(item)));
      }
    }
  }
  return Content(role: json['role'] as String?, parts: parts);
}

Map<String, Object?> _firestorePartToJson(Part part) {
  return <String, Object?>{
    if (part.text != null) 'text': part.text,
    'thought': part.thought,
    if (part.thoughtSignature != null)
      'thoughtSignature': List<int>.from(part.thoughtSignature!),
    if (part.functionCall != null)
      'functionCall': <String, Object?>{
        'name': part.functionCall!.name,
        'args': part.functionCall!.args,
        if (part.functionCall!.id != null) 'id': part.functionCall!.id,
      },
    if (part.functionResponse != null)
      'functionResponse': <String, Object?>{
        'name': part.functionResponse!.name,
        'response': part.functionResponse!.response,
        if (part.functionResponse!.id != null) 'id': part.functionResponse!.id,
      },
    if (part.inlineData != null)
      'inlineData': <String, Object?>{
        'mimeType': part.inlineData!.mimeType,
        'data': part.inlineData!.data,
        if (part.inlineData!.displayName != null)
          'displayName': part.inlineData!.displayName,
      },
    if (part.fileData != null)
      'fileData': <String, Object?>{
        'fileUri': part.fileData!.fileUri,
        if (part.fileData!.mimeType != null)
          'mimeType': part.fileData!.mimeType,
        if (part.fileData!.displayName != null)
          'displayName': part.fileData!.displayName,
      },
    if (part.executableCode != null) 'executableCode': part.executableCode,
    if (part.codeExecutionResult != null)
      'codeExecutionResult': part.codeExecutionResult,
  };
}

Part _firestorePartFromJson(Map<String, Object?> json) {
  FunctionCall? functionCall;
  final Object? rawFc = json['functionCall'] ?? json['function_call'];
  if (rawFc is Map) {
    final Map<String, Object?> fcMap = _castStringObjectMap(rawFc);
    functionCall = FunctionCall(
      name: '${fcMap['name'] ?? ''}',
      args: fcMap['args'] is Map
          ? (fcMap['args'] as Map).map(
              (Object? k, Object? v) => MapEntry('$k', v),
            )
          : <String, dynamic>{},
      id: fcMap['id'] as String?,
    );
  }

  FunctionResponse? functionResponse;
  final Object? rawFr = json['functionResponse'] ?? json['function_response'];
  if (rawFr is Map) {
    final Map<String, Object?> frMap = _castStringObjectMap(rawFr);
    functionResponse = FunctionResponse(
      name: '${frMap['name'] ?? ''}',
      response: frMap['response'] is Map
          ? (frMap['response'] as Map).map(
              (Object? k, Object? v) => MapEntry('$k', v),
            )
          : <String, dynamic>{},
      id: frMap['id'] as String?,
    );
  }

  InlineData? inlineData;
  final Object? rawInline = json['inlineData'] ?? json['inline_data'];
  if (rawInline is Map) {
    final Map<String, Object?> inlineMap = _castStringObjectMap(rawInline);
    final List<int> bytes = <int>[];
    if (inlineMap['data'] is List) {
      for (final Object? item in inlineMap['data'] as List) {
        if (item is num) {
          bytes.add(item.toInt());
        }
      }
    }
    inlineData = InlineData(
      mimeType: '${inlineMap['mimeType'] ?? inlineMap['mime_type'] ?? ''}',
      data: bytes,
      displayName:
          (inlineMap['displayName'] ?? inlineMap['display_name']) as String?,
    );
  }

  FileData? fileData;
  final Object? rawFile = json['fileData'] ?? json['file_data'];
  if (rawFile is Map) {
    final Map<String, Object?> fileMap = _castStringObjectMap(rawFile);
    fileData = FileData(
      fileUri: '${fileMap['fileUri'] ?? fileMap['file_uri'] ?? ''}',
      mimeType: (fileMap['mimeType'] ?? fileMap['mime_type']) as String?,
      displayName:
          (fileMap['displayName'] ?? fileMap['display_name']) as String?,
    );
  }

  List<int>? thoughtSignature;
  final Object? rawSig = json['thoughtSignature'] ?? json['thought_signature'];
  if (rawSig is List) {
    thoughtSignature = rawSig
        .whereType<num>()
        .map((num n) => n.toInt())
        .toList();
  }

  return Part(
    text: json['text'] as String?,
    thought: (json['thought'] as bool?) ?? false,
    thoughtSignature: thoughtSignature,
    functionCall: functionCall,
    functionResponse: functionResponse,
    inlineData: inlineData,
    fileData: fileData,
    executableCode: json['executableCode'] ?? json['executable_code'],
    codeExecutionResult:
        json['codeExecutionResult'] ?? json['code_execution_result'],
  );
}

/// Redis-backed session service and configuration for ADK.
library;

import 'dart:async';
import 'dart:convert';

import '../../errors/already_exists_error.dart';
import '../../errors/session_not_found_error.dart';
import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../events/ui_widget.dart';
import '../../platform/time.dart';
import '../../sessions/base_session_service.dart';
import '../../sessions/session.dart';
import '../../sessions/session_util.dart';
import '../../sessions/state.dart';
import '../../types/content.dart';
import '../../types/id.dart';

/// Default TTL in seconds for Redis session keys (7 days).
const int defaultRedisTtlSeconds = 604800;

/// Default key prefix used for Redis session storage.
const String defaultRedisKeyPrefix = 'adk:session:';

/// Configuration options for [RedisSessionService].
///
/// ```dart
/// final config = RedisSessionServiceConfig(
///   host: 'localhost',
///   port: 6379,
///   ttlSeconds: 3600,
/// );
/// ```
class RedisSessionServiceConfig {
  /// Creates a configuration for [RedisSessionService].
  RedisSessionServiceConfig({
    this.uri,
    this.host = 'localhost',
    this.port = 6379,
    this.password,
    this.ssl = false,
    this.db = 0,
    this.ttlSeconds = defaultRedisTtlSeconds,
    this.keyPrefix = defaultRedisKeyPrefix,
  });

  /// Redis connection URI (for example `redis://[:password@]host:port/db`).
  final String? uri;

  /// Redis server hostname.
  final String? host;

  /// Redis server port.
  final int? port;

  /// Password for Redis authentication.
  final String? password;

  /// Whether to use SSL for Redis connections.
  final bool ssl;

  /// Redis database index.
  final int db;

  /// TTL for session keys in seconds.
  ///
  /// When less than or equal to `0`, keys do not expire.
  final int ttlSeconds;

  /// Key prefix used for session keys in Redis.
  final String keyPrefix;

  /// Creates a [RedisSessionServiceConfig] from a JSON map.
  factory RedisSessionServiceConfig.fromJson(Map<String, Object?> json) {
    return RedisSessionServiceConfig(
      uri: json['uri'] as String?,
      host: (json['host'] as String?) ?? 'localhost',
      port: (json['port'] as num?)?.toInt() ?? 6379,
      password: json['password'] as String?,
      ssl: (json['ssl'] as bool?) ?? false,
      db: (json['db'] as num?)?.toInt() ?? 0,
      ttlSeconds:
          (json['ttl_seconds'] as num?)?.toInt() ??
          (json['ttlSeconds'] as num?)?.toInt() ??
          defaultRedisTtlSeconds,
      keyPrefix:
          (json['key_prefix'] as String?) ??
          (json['keyPrefix'] as String?) ??
          defaultRedisKeyPrefix,
    );
  }

  /// Serializes this configuration to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (uri != null) 'uri': uri,
      'host': host,
      'port': port,
      if (password != null) 'password': password,
      'ssl': ssl,
      'db': db,
      'ttl_seconds': ttlSeconds,
      'key_prefix': keyPrefix,
    };
  }
}

/// Injectable client interface for Redis key-value and transaction operations.
///
/// ```dart
/// final client = RedisStoreClient.inMemory();
/// await client.set('key', 'value', exSeconds: 60);
/// final value = await client.get('key');
/// ```
abstract class RedisStoreClient {
  /// Creates a Redis store client.
  RedisStoreClient();

  /// Creates an in-memory [RedisStoreClient] suitable for local execution and testing.
  factory RedisStoreClient.inMemory() = InMemoryRedisStoreClient;

  /// Retrieves the string value stored at [key], or `null` when missing or expired.
  Future<String?> get(String key);

  /// Stores [value] at [key].
  ///
  /// When [nx] is `true`, sets the key only if it does not already exist.
  /// When [exSeconds] is positive, sets an expiration TTL in seconds.
  /// Returns `true` if the key was written, or `false` when [nx] prevented writing.
  Future<bool> set(
    String key,
    String value, {
    bool nx = false,
    int? exSeconds,
  });

  /// Deletes [key] from the store.
  Future<void> delete(String key);

  /// Returns `true` if [key] exists and has not expired.
  Future<bool> exists(String key);

  /// Returns all non-expired keys matching the Redis glob [match].
  Stream<String> scanIter({required String match});

  /// Executes [action] atomically while watching [watchedKey].
  Future<void> transaction(
    Future<void> Function(RedisStoreClient pipe) action,
    String watchedKey,
  );
}

class _RedisEntry {
  _RedisEntry({required this.value, this.expiresAt});

  final String value;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!);
}

/// In-memory implementation of [RedisStoreClient] supporting TTLs and glob matching.
class InMemoryRedisStoreClient extends RedisStoreClient {
  /// Creates an in-memory Redis store client.
  InMemoryRedisStoreClient();

  final Map<String, _RedisEntry> _store = <String, _RedisEntry>{};
  Future<void> _txLock = Future<void>.value();

  void _evictIfExpired(String key) {
    final _RedisEntry? entry = _store[key];
    if (entry != null && entry.isExpired) {
      _store.remove(key);
    }
  }

  /// Returns the remaining TTL in seconds for [key], or `null` if no TTL is set.
  int? ttlSeconds(String key) {
    _evictIfExpired(key);
    final _RedisEntry? entry = _store[key];
    if (entry == null || entry.expiresAt == null) {
      return null;
    }
    final int remaining = entry.expiresAt!
        .difference(DateTime.now().toUtc())
        .inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  Future<String?> get(String key) async {
    _evictIfExpired(key);
    return _store[key]?.value;
  }

  @override
  Future<bool> set(
    String key,
    String value, {
    bool nx = false,
    int? exSeconds,
  }) async {
    _evictIfExpired(key);
    if (nx && _store.containsKey(key)) {
      return false;
    }
    final DateTime? expiresAt = (exSeconds != null && exSeconds > 0)
        ? DateTime.now().toUtc().add(Duration(seconds: exSeconds))
        : null;
    _store[key] = _RedisEntry(value: value, expiresAt: expiresAt);
    return true;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<bool> exists(String key) async {
    _evictIfExpired(key);
    return _store.containsKey(key);
  }

  @override
  Stream<String> scanIter({required String match}) async* {
    final RegExp regex = _globToRegExp(match);
    final List<String> keys = _store.keys.toList(growable: false);
    for (final String key in keys) {
      _evictIfExpired(key);
      if (_store.containsKey(key) && regex.hasMatch(key)) {
        yield key;
      }
    }
  }

  @override
  Future<void> transaction(
    Future<void> Function(RedisStoreClient pipe) action,
    String watchedKey,
  ) async {
    final Completer<void> next = Completer<void>();
    final Future<void> previous = _txLock;
    _txLock = next.future;
    try {
      await previous;
      await action(this);
    } finally {
      next.complete();
    }
  }
}

/// Escapes Redis glob metacharacters in [value] so that it matches only itself.
String escapeRedisGlob(String value) {
  return value.replaceAllMapped(
    RegExp(r'([\\*?\[\]])'),
    (Match match) => '\\${match.group(1)}',
  );
}

RegExp _globToRegExp(String pattern) {
  final StringBuffer buffer = StringBuffer('^');
  for (int i = 0; i < pattern.length; i += 1) {
    final String ch = pattern[i];
    if (ch == r'\' && i + 1 < pattern.length) {
      i += 1;
      buffer.write(RegExp.escape(pattern[i]));
      continue;
    }
    if (ch == '*') {
      buffer.write('.*');
    } else if (ch == '?') {
      buffer.write('.');
    } else {
      buffer.write(RegExp.escape(ch));
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}

/// Redis-backed session service for ADK.
///
/// Stores session objects, events, and `app:` / `user:` state in Redis using
/// [RedisStoreClient].
///
/// ```dart
/// final service = RedisSessionService(
///   config: RedisSessionServiceConfig(ttlSeconds: 3600),
/// );
/// final session = await service.createSession(
///   appName: 'my_app',
///   userId: 'user_1',
///   state: {'app:version': '1.0', 'user:lang': 'en', 'count': 1},
/// );
/// ```
class RedisSessionService extends BaseSessionService {
  /// Creates a Redis session service.
  ///
  /// Uses [redisClient] when provided, or an [InMemoryRedisStoreClient] by default.
  RedisSessionService({
    RedisSessionServiceConfig? config,
    RedisStoreClient? redisClient,
  }) : config = config ?? RedisSessionServiceConfig(),
       _redisClient = redisClient ?? InMemoryRedisStoreClient();

  /// Configuration for Redis connection and key management.
  final RedisSessionServiceConfig config;

  final RedisStoreClient _redisClient;

  /// Returns the underlying [RedisStoreClient].
  RedisStoreClient get redisClient => _redisClient;

  String _sessionKey(String appName, String userId, String sessionId) =>
      '${config.keyPrefix}$appName:$userId:$sessionId';

  String _userStateKey(String appName, String userId) =>
      '${config.keyPrefix}user_state:$appName:$userId';

  String _appStateKey(String appName) =>
      '${config.keyPrefix}app_state:$appName';

  int? get _effectiveTtl => config.ttlSeconds > 0 ? config.ttlSeconds : null;

  static Map<String, Object?> _mergeState({
    Map<String, Object?>? appState,
    Map<String, Object?>? userState,
    required Map<String, Object?> sessionState,
  }) {
    final Map<String, Object?> mergedState = _deepCopyMap(sessionState);
    if (appState != null) {
      appState.forEach((String key, Object? value) {
        mergedState['${State.appPrefix}$key'] = value;
      });
    }
    if (userState != null) {
      userState.forEach((String key, Object? value) {
        mergedState['${State.userPrefix}$key'] = value;
      });
    }
    return mergedState;
  }

  static Map<String, Object?> _extractSessionOnlyState(
    Map<String, Object?> state,
  ) {
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in state.entries)
        if (!entry.key.startsWith(State.appPrefix) &&
            !entry.key.startsWith(State.userPrefix) &&
            !entry.key.startsWith(State.tempPrefix))
          entry.key: entry.value,
    };
  }

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    final String sid = (sessionId != null && sessionId.trim().isNotEmpty)
        ? sessionId.trim()
        : newAdkId(prefix: 'session_');
    final String key = _sessionKey(appName, userId, sid);

    final Map<String, Object?> initialState = state ?? <String, Object?>{};
    final SessionStateDelta stateDeltas = extractStateDelta(initialState);
    final Map<String, Object?> appStateDelta = stateDeltas.app;
    final Map<String, Object?> userStateDelta = stateDeltas.user;
    final Map<String, Object?> sessionState = stateDeltas.session;

    final String appKey = _appStateKey(appName);
    final String userKey = _userStateKey(appName, userId);

    final List<String?> rawStates = await Future.wait(<Future<String?>>[
      _redisClient.get(appKey),
      _redisClient.get(userKey),
    ]);
    final Map<String, Object?> currentApp = _decodeJsonMap(rawStates[0]);
    final Map<String, Object?> currentUser = _decodeJsonMap(rawStates[1]);

    if (appStateDelta.isNotEmpty) {
      currentApp.addAll(appStateDelta);
      await _redisClient.set(
        appKey,
        jsonEncode(currentApp),
        exSeconds: _effectiveTtl,
      );
    }

    if (userStateDelta.isNotEmpty) {
      currentUser.addAll(userStateDelta);
      await _redisClient.set(
        userKey,
        jsonEncode(currentUser),
        exSeconds: _effectiveTtl,
      );
    }

    final double now = getTime();
    final Session storageSession = Session(
      id: sid,
      appName: appName,
      userId: userId,
      state: sessionState,
      events: <Event>[],
      lastUpdateTime: now,
    );

    final bool created = await _redisClient.set(
      key,
      jsonEncode(_redisSessionToJson(storageSession)),
      nx: true,
      exSeconds: _effectiveTtl,
    );
    if (!created) {
      throw AlreadyExistsError(
        'Session $sid already exists for user $userId in app $appName.',
      );
    }

    final Map<String, Object?> mergedState = _mergeState(
      appState: currentApp,
      userState: currentUser,
      sessionState: sessionState,
    );
    initialState.forEach((String k, Object? v) {
      if (k.startsWith(State.tempPrefix)) {
        mergedState[k] = v;
      }
    });

    return Session(
      id: sid,
      appName: appName,
      userId: userId,
      state: mergedState,
      events: <Event>[],
      lastUpdateTime: now,
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    final String key = _sessionKey(appName, userId, sessionId);
    final String appKey = _appStateKey(appName);
    final String userKey = _userStateKey(appName, userId);

    final List<String?> rawValues = await Future.wait(<Future<String?>>[
      _redisClient.get(key),
      _redisClient.get(appKey),
      _redisClient.get(userKey),
    ]);
    final String? raw = rawValues[0];
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final Session session = _redisSessionFromJson(_decodeJsonMap(raw));
    final Map<String, Object?> appState = _decodeJsonMap(rawValues[1]);
    final Map<String, Object?> userState = _decodeJsonMap(rawValues[2]);
    session.state = _mergeState(
      appState: appState,
      userState: userState,
      sessionState: session.state,
    );

    if (config != null) {
      if (config.numRecentEvents != null) {
        final int count = config.numRecentEvents!;
        if (count == 0) {
          session.events = <Event>[];
        } else if (session.events.length > count) {
          session.events = session.events.sublist(
            session.events.length - count,
          );
        }
      }
      if (config.afterTimestamp != null) {
        session.events = session.events
            .where((Event e) => e.timestamp >= config.afterTimestamp!)
            .toList();
      }
    }
    return session;
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    final String escapedAppName = escapeRedisGlob(appName);
    final String pattern = userId != null
        ? '${config.keyPrefix}$escapedAppName:${escapeRedisGlob(userId)}:*'
        : '${config.keyPrefix}$escapedAppName:*';

    final String? appRaw = await _redisClient.get(_appStateKey(appName));
    final Map<String, Object?> appState = _decodeJsonMap(appRaw);

    final Map<String, Map<String, Object?>> userStatesMap =
        <String, Map<String, Object?>>{};
    if (userId != null) {
      final String? userRaw = await _redisClient.get(
        _userStateKey(appName, userId),
      );
      if (userRaw != null && userRaw.isNotEmpty) {
        userStatesMap[userId] = _decodeJsonMap(userRaw);
      }
    }

    final List<Session> sessions = <Session>[];
    await for (final String key in _redisClient.scanIter(match: pattern)) {
      if (key.startsWith('${config.keyPrefix}user_state:') ||
          key.startsWith('${config.keyPrefix}app_state:')) {
        continue;
      }
      final String? raw = await _redisClient.get(key);
      if (raw == null || raw.isEmpty) {
        continue;
      }
      try {
        final Session s = _redisSessionFromJson(_decodeJsonMap(raw));
        if (s.appName != appName || (userId != null && s.userId != userId)) {
          continue;
        }
        final String uId = s.userId;
        if (!userStatesMap.containsKey(uId)) {
          final String? uRaw = await _redisClient.get(
            _userStateKey(appName, uId),
          );
          userStatesMap[uId] = _decodeJsonMap(uRaw);
        }
        s.state = _mergeState(
          appState: appState,
          userState: userStatesMap[uId],
          sessionState: s.state,
        );
        sessions.add(s);
      } catch (_) {
        // Ignore unparseable session payloads.
      }
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
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    final String key = _sessionKey(appName, userId, sessionId);
    await _redisClient.delete(key);
  }

  @override
  Future<Map<String, Object?>> getUserState({
    required String appName,
    required String userId,
  }) async {
    final String userKey = _userStateKey(appName, userId);
    final String? raw = await _redisClient.get(userKey);
    return _decodeJsonMap(raw);
  }

  @override
  Future<Event> appendEvent({
    required Session session,
    required Event event,
  }) async {
    final String key = _sessionKey(
      session.appName,
      session.userId,
      session.id,
    );
    if (!await _redisClient.exists(key)) {
      throw SessionNotFoundError('Session ${session.id} not found.');
    }

    final Event appended = await super.appendEvent(
      session: session,
      event: event,
    );
    session.lastUpdateTime = appended.timestamp;

    Map<String, Object?> sessionDelta = <String, Object?>{};
    if (appended.actions.stateDelta.isNotEmpty) {
      final SessionStateDelta deltas = extractStateDelta(
        appended.actions.stateDelta,
      );
      final Map<String, Object?> appDelta = deltas.app;
      final Map<String, Object?> userDelta = deltas.user;
      sessionDelta = deltas.session;

      if (appDelta.isNotEmpty) {
        final String appKey = _appStateKey(session.appName);
        final String? appRaw = await _redisClient.get(appKey);
        final Map<String, Object?> appState = _decodeJsonMap(appRaw);
        appState.addAll(appDelta);
        await _redisClient.set(
          appKey,
          jsonEncode(appState),
          exSeconds: _effectiveTtl,
        );
      }

      if (userDelta.isNotEmpty) {
        final String userKey = _userStateKey(session.appName, session.userId);
        final String? userRaw = await _redisClient.get(userKey);
        final Map<String, Object?> userState = _decodeJsonMap(userRaw);
        userState.addAll(userDelta);
        await _redisClient.set(
          userKey,
          jsonEncode(userState),
          exSeconds: _effectiveTtl,
        );
      }
    }

    final Map<String, Object?> sessionOnlyState = _extractSessionOnlyState(
      session.state,
    );
    final Session storageSession = Session(
      id: session.id,
      appName: session.appName,
      userId: session.userId,
      state: sessionOnlyState,
      events: List<Event>.from(session.events),
      lastUpdateTime: session.lastUpdateTime,
    );

    await _redisClient.transaction((RedisStoreClient pipe) async {
      final String? raw = await pipe.get(key);
      if (raw != null && raw.isNotEmpty) {
        final Session storedSession = _redisSessionFromJson(
          _decodeJsonMap(raw),
        );
        storageSession.events = storedSession.events;
        storageSession.state = storedSession.state;
        if (appended.partial != true) {
          storageSession.events.add(appended);
          if (sessionDelta.isNotEmpty) {
            storageSession.state.addAll(sessionDelta);
          }
        }
      } else {
        storageSession.events = List<Event>.from(session.events);
        storageSession.state = Map<String, Object?>.from(sessionOnlyState);
      }
      await pipe.set(
        key,
        jsonEncode(_redisSessionToJson(storageSession)),
        exSeconds: _effectiveTtl,
      );
    }, key);

    return appended;
  }
}

Map<String, Object?> _decodeJsonMap(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return <String, Object?>{};
  }
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((Object? k, Object? v) => MapEntry('$k', v));
    }
  } catch (_) {
    // Ignore malformed JSON.
  }
  return <String, Object?>{};
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

Map<String, Object?> _castMap(Object? value) {
  if (value is Map) {
    return value.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  return <String, Object?>{};
}

Map<String, Object?> _redisSessionToJson(Session session) {
  return <String, Object?>{
    'id': session.id,
    'app_name': session.appName,
    'user_id': session.userId,
    'state': session.state,
    'events': session.events.map(_redisEventToJson).toList(),
    'last_update_time': session.lastUpdateTime,
  };
}

Session _redisSessionFromJson(Map<String, Object?> json) {
  final List<Event> events = <Event>[];
  if (json['events'] is List) {
    for (final Object? item in json['events'] as List) {
      if (item is Map) {
        events.add(_redisEventFromJson(_castMap(item)));
      }
    }
  }
  final Object? rawLastUpdate =
      json['last_update_time'] ?? json['lastUpdateTime'];
  return Session(
    id: '${json['id'] ?? ''}',
    appName: '${json['app_name'] ?? json['appName'] ?? ''}',
    userId: '${json['user_id'] ?? json['userId'] ?? ''}',
    state: _castMap(json['state']),
    events: events,
    lastUpdateTime: (rawLastUpdate is num) ? rawLastUpdate.toDouble() : 0.0,
  );
}

Map<String, Object?> _redisEventToJson(Event event) {
  return <String, Object?>{
    'invocationId': event.invocationId,
    'author': event.author,
    'id': event.id,
    'timestamp': event.timestamp,
    'actions': _redisEventActionsToJson(event.actions),
    if (!event.nodeInfo.isEmpty)
      'nodeInfo': eventNodeInfoToJson(event.nodeInfo),
    if (event.hasOutput) 'output': event.output,
    if (event.longRunningToolIds != null)
      'longRunningToolIds': event.longRunningToolIds!.toList(),
    if (event.branch != null) 'branch': event.branch,
    if (event.isolationScope != null) 'isolationScope': event.isolationScope,
    if (event.modelVersion != null) 'modelVersion': event.modelVersion,
    if (event.content != null) 'content': _redisContentToJson(event.content!),
    if (event.partial != null) 'partial': event.partial,
    if (event.turnComplete != null) 'turnComplete': event.turnComplete,
    if (event.finishReason != null) 'finishReason': event.finishReason,
    if (event.errorCode != null) 'errorCode': event.errorCode,
    if (event.errorMessage != null) 'errorMessage': event.errorMessage,
    if (event.interrupted != null) 'interrupted': event.interrupted,
    if (event.customMetadata != null) 'customMetadata': event.customMetadata,
  };
}

Event _redisEventFromJson(Map<String, Object?> json) {
  final Event event = Event(
    invocationId: '${json['invocationId'] ?? json['invocation_id'] ?? ''}',
    author: '${json['author'] ?? ''}',
    id: '${json['id'] ?? ''}',
    timestamp: (json['timestamp'] is num)
        ? (json['timestamp'] as num).toDouble()
        : 0.0,
    actions: _redisEventActionsFromJson(_castMap(json['actions'])),
    nodeInfo: eventNodeInfoFromJson(
      _castMap(json['nodeInfo'] ?? json['node_info']),
    ),
    longRunningToolIds: (json['longRunningToolIds'] is List)
        ? (json['longRunningToolIds'] as List).whereType<String>().toSet()
        : null,
    branch: json['branch'] as String?,
    isolationScope:
        (json['isolationScope'] ?? json['isolation_scope']) as String?,
    modelVersion: (json['modelVersion'] ?? json['model_version']) as String?,
    content: json['content'] is Map
        ? _redisContentFromJson(_castMap(json['content']))
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
  );
  if (json.containsKey('output')) {
    event.output = json['output'];
    event.hasOutput = true;
  }
  return event;
}

Map<String, Object?> _redisEventActionsToJson(EventActions actions) {
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
        'compactedContent': _redisContentToJson(
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

EventActions _redisEventActionsFromJson(Map<String, Object?> json) {
  EventCompaction? compaction;
  if (json['compaction'] is Map) {
    final Map<String, Object?> compactionMap = _castMap(json['compaction']);
    compaction = EventCompaction(
      startTimestamp: (compactionMap['startTimestamp'] is num)
          ? (compactionMap['startTimestamp'] as num).toDouble()
          : 0.0,
      endTimestamp: (compactionMap['endTimestamp'] is num)
          ? (compactionMap['endTimestamp'] as num).toDouble()
          : 0.0,
      compactedContent: _redisContentFromJson(
        _castMap(compactionMap['compactedContent']),
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
  return EventActions(
    skipSummarization:
        (json['skipSummarization'] ?? json['skip_summarization']) as bool?,
    stateDelta: _castMap(json['stateDelta'] ?? json['state_delta']),
    artifactDelta: artifactDelta,
    transferToAgent:
        (json['transferToAgent'] ?? json['transfer_to_agent']) as String?,
    escalate: json['escalate'] as bool?,
    compaction: compaction,
    endOfAgent: (json['endOfAgent'] ?? json['end_of_agent']) as bool?,
    agentState: json['agentState'] is Map ? _castMap(json['agentState']) : null,
    rewindBeforeInvocationId:
        (json['rewindBeforeInvocationId'] ?? json['rewind_before_invocation_id'])
            as String?,
    route: json['route'],
  );
}

Map<String, Object?> _redisContentToJson(Content content) {
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map(_redisPartToJson).toList(),
  };
}

Content _redisContentFromJson(Map<String, Object?> json) {
  final List<Part> parts = <Part>[];
  if (json['parts'] is List) {
    for (final Object? item in json['parts'] as List) {
      if (item is Map) {
        parts.add(_redisPartFromJson(_castMap(item)));
      }
    }
  }
  return Content(role: json['role'] as String?, parts: parts);
}

Map<String, Object?> _redisPartToJson(Part part) {
  return <String, Object?>{
    if (part.text != null) 'text': part.text,
    'thought': part.thought,
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
  };
}

Part _redisPartFromJson(Map<String, Object?> json) {
  FunctionCall? functionCall;
  final Object? rawFc = json['functionCall'] ?? json['function_call'];
  if (rawFc is Map) {
    final Map<String, Object?> fcMap = _castMap(rawFc);
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
    final Map<String, Object?> frMap = _castMap(rawFr);
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
  return Part(
    text: json['text'] as String?,
    thought: (json['thought'] as bool?) ?? false,
    functionCall: functionCall,
    functionResponse: functionResponse,
  );
}

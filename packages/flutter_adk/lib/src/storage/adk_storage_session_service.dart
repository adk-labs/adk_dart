import 'dart:convert';
import 'package:adk_dart/adk_core.dart' as adk;
import 'adk_storage.dart';

/// A [adk.BaseSessionService] implementation backed by an [AdkKeyValueStorage].
///
/// This enables seamless persistent conversation sessions using `shared_preferences`,
/// `flutter_secure_storage`, or any custom storage backend.
class AdkStorageSessionService extends adk.BaseSessionService {
  /// Creates an [AdkStorageSessionService] backed by [storage].
  AdkStorageSessionService({
    AdkKeyValueStorage? storage,
    this.keyPrefix = 'adk_session_',
  }) : storage = storage ?? AdkMemoryStorage();

  /// Creates an [AdkStorageSessionService] with in-memory storage.
  factory AdkStorageSessionService.inMemory() => AdkStorageSessionService();

  /// Creates an [AdkStorageSessionService] from simple functional delegates.
  factory AdkStorageSessionService.custom({
    required dynamic Function(String key) read,
    required dynamic Function(String key, String value) write,
    required dynamic Function(String key) delete,
    required dynamic Function({String prefix}) getKeys,
    String keyPrefix = 'adk_session_',
  }) {
    return AdkStorageSessionService(
      storage: AdkCustomStorage(
        read: (k) async => (await read(k))?.toString(),
        write: (k, v) async => await write(k, v),
        delete: (k) async => await delete(k),
        getKeys: ({prefix = ''}) async =>
            (await getKeys(prefix: prefix) as List).map((e) => e.toString()).toList(),
      ),
      keyPrefix: keyPrefix,
    );
  }

  /// The underlying storage engine.
  final AdkKeyValueStorage storage;

  /// Key prefix used to namespace stored sessions.
  final String keyPrefix;

  String _buildKey(String appName, String userId, String sessionId) =>
      '$keyPrefix${appName}_${userId}_$sessionId';

  @override
  Future<adk.Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    final String resolvedId = (sessionId != null && sessionId.trim().isNotEmpty)
        ? sessionId.trim()
        : adk.newAdkId(prefix: 'session_');

    final existing = await getSession(
      appName: appName,
      userId: userId,
      sessionId: resolvedId,
    );

    if (existing != null) {
      throw adk.AlreadyExistsError('Session with id $resolvedId already exists.');
    }

    final deltas = adk.extractStateDelta(state);

    final session = adk.Session(
      id: resolvedId,
      appName: appName,
      userId: userId,
      state: deltas.session,
      lastUpdateTime: adk.getTime(),
    );

    await _save(session);
    return session;
  }

  @override
  Future<adk.Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    adk.GetSessionConfig? config,
  }) async {
    final key = _buildKey(appName, userId, sessionId);
    final raw = await storage.read(key);
    if (raw == null) {
      return null;
    }

    try {
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
      final storageSession = adk.StorageSessionV1.fromJson(jsonMap);
      final events = storageSession.storageEvents
          .map((adk.StorageEventV1 e) => e.toEvent())
          .toList();

      final session = storageSession.toSession(events: events);

      if (config?.numRecentEvents != null &&
          config!.numRecentEvents! > 0 &&
          session.events.length > config.numRecentEvents!) {
        final subset = session.events
            .sublist(session.events.length - config.numRecentEvents!);
        return session.copyWith(events: subset);
      }

      return session;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<adk.ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    final prefix = userId != null
        ? '$keyPrefix${appName}_${userId}_'
        : '$keyPrefix${appName}_';

    final keys = await storage.getKeys(prefix: prefix);
    final sessions = <adk.Session>[];

    for (final key in keys) {
      final raw = await storage.read(key);
      if (raw != null) {
        try {
          final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
          final storageSession = adk.StorageSessionV1.fromJson(jsonMap);
          final events = storageSession.storageEvents
              .map((adk.StorageEventV1 e) => e.toEvent())
              .toList();
          sessions.add(storageSession.toSession(events: events));
        } catch (_) {
          // ignore corrupted entries
        }
      }
    }

    sessions.sort((a, b) => b.lastUpdateTime.compareTo(a.lastUpdateTime));
    return adk.ListSessionsResponse(sessions: sessions);
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    final key = _buildKey(appName, userId, sessionId);
    await storage.delete(key);
  }

  @override
  Future<adk.Event> appendEvent({
    required adk.Session session,
    required adk.Event event,
  }) async {
    final persisted = await super.appendEvent(session: session, event: event);
    await _save(session);
    return persisted;
  }

  Future<void> _save(adk.Session session) async {
    final key = _buildKey(session.appName, session.userId, session.id);
    final storageEvents = session.events
        .map((adk.Event e) => adk.StorageEventV1.fromEvent(session: session, event: e))
        .toList();

    final storageSession = adk.StorageSessionV1(
      appName: session.appName,
      userId: session.userId,
      id: session.id,
      state: session.state,
      updateTime: adk.PreciseTimestamp.fromSeconds(session.lastUpdateTime),
      storageEvents: storageEvents,
    );

    final jsonStr = jsonEncode(storageSession.toJson());
    await storage.write(key, jsonStr);
  }
}

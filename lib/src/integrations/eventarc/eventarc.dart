/// Google Cloud Eventarc Advanced integration and per-loop publisher client cache.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../../agents/readonly_context.dart';
import '../../features/_feature_registry.dart';
import '../../platform/time.dart';
import '../../tools/base_tool.dart';
import '../../tools/base_toolset.dart';
import '../../tools/eventarc/config.dart';
import '../../tools/eventarc/message_tool.dart' as message_tool;
import '../../tools/google_tool.dart';
import '../../version.dart';

export '../../tools/eventarc/config.dart';
export '../../tools/eventarc/message_tool.dart';

const double _cacheTtlSeconds = 1800.0;
const int _cacheMaxSize = 10;
final Symbol _loopScopeZoneKey = #_adkEventarcLoopScope;

/// Client abstraction for Eventarc Advanced publishing.
abstract class EventarcPublisherClient {
  /// Optional user agent string configured on this client.
  String? get userAgent => null;

  /// Closes the underlying transport and releases resources.
  FutureOr<void> close();
}

/// Default in-memory [EventarcPublisherClient] implementation.
class DefaultEventarcPublisherClient extends EventarcPublisherClient {
  /// Creates a publisher client for [credentials] and [userAgent].
  DefaultEventarcPublisherClient({this.credentials, this.userAgent});

  /// Credentials associated with this client.
  final Object? credentials;

  @override
  final String? userAgent;

  /// Whether [close] has been called on this client.
  bool isClosed = false;

  @override
  Future<void> close() async {
    isClosed = true;
  }
}

/// Factory signature for creating [EventarcPublisherClient] instances.
typedef EventarcPublisherClientFactory =
    EventarcPublisherClient Function({Object? credentials, String? userAgent});

EventarcPublisherClientFactory _publisherClientFactory =
    ({Object? credentials, String? userAgent}) =>
        DefaultEventarcPublisherClient(
          credentials: credentials,
          userAgent: userAgent,
        );

/// Overrides the factory used by [getPublisherClient].
void setEventarcPublisherClientFactory(EventarcPublisherClientFactory factory) {
  _publisherClientFactory = factory;
}

/// Restores the default [EventarcPublisherClient] factory.
void resetEventarcPublisherClientFactory() {
  _publisherClientFactory = ({Object? credentials, String? userAgent}) =>
      DefaultEventarcPublisherClient(
        credentials: credentials,
        userAgent: userAgent,
      );
}

/// Represents an event loop scope for Eventarc publisher client caching.
class EventarcLoopScope {
  /// Creates a loop scope.
  EventarcLoopScope({bool Function()? isClosed}) : _isClosed = isClosed;

  final bool Function()? _isClosed;
  bool _closed = false;

  /// Whether this event loop scope is closed.
  bool get isClosed => _closed || (_isClosed?.call() ?? false);

  /// Marks this event loop scope as closed.
  void markClosed() {
    _closed = true;
  }
}

/// Runs [action] inside an isolated [EventarcLoopScope].
T runWithEventarcLoopScope<T>(
  EventarcLoopScope scope,
  T Function() action,
) {
  return runZoned(
    action,
    zoneValues: <Object?, Object?>{_loopScopeZoneKey: scope},
  );
}

typedef _CacheKey = (String?, String, int, String);
typedef _CacheEntry = (EventarcPublisherClient, double);

class _PerLoopPublisherCache {
  final Map<Object, LinkedHashMap<_CacheKey, _CacheEntry>> _byLoop =
      <Object, LinkedHashMap<_CacheKey, _CacheEntry>>{};

  Object _currentLoopKey() {
    final Object? zoneScope = Zone.current[_loopScopeZoneKey];
    return zoneScope ?? Zone.root;
  }

  void _evictClosedLoops() {
    _byLoop.removeWhere((Object key, _) {
      return key is EventarcLoopScope && key.isClosed;
    });
  }

  LinkedHashMap<_CacheKey, _CacheEntry> get() {
    _evictClosedLoops();
    final Object key = _currentLoopKey();
    return _byLoop.putIfAbsent(
      key,
      () => LinkedHashMap<_CacheKey, _CacheEntry>(),
    );
  }

  /// Number of active loop caches currently tracked.
  int get loopCount => _byLoop.length;

  /// Clears all loop caches across all scopes.
  void clearAll() {
    _byLoop.clear();
  }
}

final _PerLoopPublisherCache _publisherClientCache = _PerLoopPublisherCache();

/// Returns the number of active loop-scoped caches (for testing).
int get eventarcCachedLoopCount => _publisherClientCache.loopCount;

String _getFinalUserAgent(String? userAgent) {
  const String baseAgent = 'google-adk/$adkVersion';
  if (userAgent == null || userAgent.trim().isEmpty) {
    return baseAgent;
  }
  return '$baseAgent ${userAgent.trim()}';
}

String _getCredentialId(Object? credentials) {
  if (credentials == null) {
    return 'default';
  }
  return '${identityHashCode(credentials)}';
}

_CacheKey _getCacheKey({
  required Object? credentials,
  required String finalUserAgent,
  String? projectId,
}) {
  return (projectId, finalUserAgent, pid, _getCredentialId(credentials));
}

Future<void> _closeClient(EventarcPublisherClient client) async {
  try {
    await client.close();
  } catch (_) {
    // Ignore close errors.
  }
}

/// Gets or creates the current event loop's [EventarcPublisherClient].
Future<EventarcPublisherClient> getPublisherClient({
  Object? credentials,
  String? userAgent,
  String? projectId,
}) async {
  final LinkedHashMap<_CacheKey, _CacheEntry> loopCache =
      _publisherClientCache.get();
  final String finalUserAgent = _getFinalUserAgent(userAgent);
  final _CacheKey cacheKey = _getCacheKey(
    credentials: credentials,
    finalUserAgent: finalUserAgent,
    projectId: projectId,
  );
  final double currentTime = getTime();
  EventarcPublisherClient? oldClientToClose;

  final _CacheEntry? existing = loopCache.remove(cacheKey);
  if (existing != null) {
    final (EventarcPublisherClient client, double expiration) = existing;
    if (expiration > currentTime) {
      // Re-insert at the end to maintain LRU ordering.
      loopCache[cacheKey] = existing;
      return client;
    }
  }

  final EventarcPublisherClient client = _publisherClientFactory(
    credentials: credentials,
    userAgent: finalUserAgent,
  );

  if (loopCache.length >= _cacheMaxSize) {
    final _CacheKey oldestKey = loopCache.keys.first;
    final _CacheEntry? evicted = loopCache.remove(oldestKey);
    oldClientToClose = evicted?.$1;
  }

  loopCache[cacheKey] = (client, currentTime + _cacheTtlSeconds);

  if (oldClientToClose != null) {
    await _closeClient(oldClientToClose);
  }

  return client;
}

/// Removes a publisher client from the current event loop's cache and closes it.
Future<void> removePublisherClient({
  Object? credentials,
  String? userAgent,
  String? projectId,
}) async {
  final LinkedHashMap<_CacheKey, _CacheEntry> loopCache =
      _publisherClientCache.get();
  final String finalUserAgent = _getFinalUserAgent(userAgent);
  final _CacheKey cacheKey = _getCacheKey(
    credentials: credentials,
    finalUserAgent: finalUserAgent,
    projectId: projectId,
  );

  final _CacheEntry? entry = loopCache.remove(cacheKey);
  if (entry != null) {
    await _closeClient(entry.$1);
  }
}

/// Cleans up and closes all cached publisher clients for the current event loop.
Future<void> cleanupClients() async {
  final LinkedHashMap<_CacheKey, _CacheEntry> loopCache =
      _publisherClientCache.get();
  final List<_CacheEntry> entries = loopCache.values.toList(growable: false);
  loopCache.clear();
  for (final _CacheEntry entry in entries) {
    await _closeClient(entry.$1);
  }
}

/// Toolset for publishing structured CloudEvents to Eventarc Advanced buses.
class EventarcToolset extends BaseToolset {
  /// Creates an Eventarc toolset.
  EventarcToolset({
    super.toolFilter,
    EventarcCredentialsConfig? credentialsConfig,
    EventarcToolConfig? toolConfig,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = toolConfig ?? const EventarcToolConfig();

  final EventarcCredentialsConfig? _credentialsConfig;
  final EventarcToolConfig _toolSettings;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    isFeatureEnabled(FeatureName.eventarcToolset);

    final List<GoogleTool> allTools = <GoogleTool>[
      GoogleTool(
        func: message_tool.publishMessage,
        name: 'publish_message',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
    ];

    return allTools
        .where((GoogleTool tool) => isToolSelected(tool, readonlyContext))
        .toList();
  }

  @override
  Future<void> close() async {
    await cleanupClients();
  }
}

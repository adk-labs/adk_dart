/// Production ADK API server and CORS/origin security utilities.
///
/// Mirrors `google.adk.cli.api_server`.
library;

import 'dart:io';

import 'adk_web_server.dart';

/// Alias for [AdkApiServer].
typedef ApiServer = AdkApiServer;

/// Result of splitting CORS origin specs into literal origins and a combined regex.
class CorsOriginsConfig {
  /// Creates a [CorsOriginsConfig].
  const CorsOriginsConfig({
    required this.allowOrigins,
    this.allowOriginRegex,
  });

  /// Literal origin strings (or `'*'`).
  final List<String> allowOrigins;

  /// Combined regular expression string for `regex:` prefixed origins, if any.
  final String? allowOriginRegex;
}

/// Splits raw `--allow_origins` values into literal origins and a combined regex.
CorsOriginsConfig parseCorsOrigins(List<String> origins) {
  final List<String> literals = <String>[];
  final List<String> regexParts = <String>[];
  for (final String raw in origins) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (trimmed.startsWith('regex:')) {
      final String pattern = trimmed.substring('regex:'.length);
      if (pattern.isNotEmpty) {
        regexParts.add('(?:$pattern)');
      }
    } else {
      literals.add(trimmed);
    }
  }
  return CorsOriginsConfig(
    allowOrigins: literals,
    allowOriginRegex: regexParts.isEmpty ? null : regexParts.join('|'),
  );
}

/// Returns `true` if [origin] is permitted by [allowOrigins] (supporting `'*'`
/// and `'regex:...'` entries).
bool isOriginAllowed(String origin, List<String> allowOrigins) {
  for (final String allowed in allowOrigins) {
    if (allowed == '*') {
      return true;
    }
    if (allowed == origin) {
      return true;
    }
    if (allowed.startsWith('regex:')) {
      final String pattern = allowed.substring('regex:'.length);
      if (pattern.isEmpty) {
        continue;
      }
      final RegExp regex = RegExp(pattern);
      final Match? match = regex.matchAsPrefix(origin);
      if (match != null && match.end == origin.length) {
        return true;
      }
    }
  }
  return false;
}

/// Returns `true` if [origin] is permitted for a protected mutation endpoint
/// (requires either same-origin or a literal entry in [allowOrigins]; wildcard
/// `'*'` and `'regex:'` entries do not grant access).
bool isOriginAllowedForProtectedMutation({
  required String origin,
  required String? requestOrigin,
  required List<String> allowOrigins,
}) {
  for (final String allowed in allowOrigins) {
    if (allowed == '*' || allowed.startsWith('regex:')) {
      continue;
    }
    if (allowed == origin) {
      return true;
    }
  }
  return requestOrigin != null && requestOrigin == origin;
}

/// Returns `true` if [host] (with or without port/brackets) is a loopback address.
bool isLoopbackAddress(String host) {
  String bare = host.trim();
  if (bare.startsWith('[')) {
    final int end = bare.indexOf(']');
    if (end != -1) {
      bare = bare.substring(1, end);
    }
  } else if (bare.split(':').length == 2) {
    bare = bare.substring(0, bare.lastIndexOf(':'));
  }
  if (bare.toLowerCase() == 'localhost') {
    return true;
  }
  try {
    return InternetAddress(bare).isLoopback;
  } on ArgumentError {
    return false;
  }
}

/// Returns `true` if a client connection is direct from a local loopback address
/// without reverse-proxy forwarding headers.
bool isLocalClient({
  String? remoteAddress,
  Map<String, String>? headers,
}) {
  if (headers != null) {
    for (final MapEntry<String, String> entry in headers.entries) {
      final String lower = entry.key.toLowerCase();
      if ((lower == 'forwarded' ||
              lower == 'x-forwarded-for' ||
              lower == 'x-forwarded-host') &&
          entry.value.trim().isNotEmpty) {
        return false;
      }
    }
  }
  if (remoteAddress == null || remoteAddress.trim().isEmpty) {
    return false;
  }
  return isLoopbackAddress(remoteAddress);
}

/// Returns `true` if a request to a loopback-bound server with no explicit
/// [allowOrigins] carries a non-loopback `Origin` header (DNS rebinding guard).
bool isDnsRebindingRequest({
  required String origin,
  required String? serverHost,
  required List<String> allowOrigins,
}) {
  if (allowOrigins.isNotEmpty ||
      serverHost == null ||
      !isLoopbackAddress(serverHost)) {
    return false;
  }
  final String originHost = Uri.tryParse(origin)?.host ?? '';
  return !isLoopbackAddress(originHost);
}

/// Evaluates whether [origin] is allowed for a state-changing request.
bool isRequestOriginAllowed({
  required String origin,
  required String? requestOrigin,
  required List<String> allowOrigins,
  String? serverHost,
}) {
  if (allowOrigins.isNotEmpty && isOriginAllowed(origin, allowOrigins)) {
    return true;
  }
  if (isDnsRebindingRequest(
    origin: origin,
    serverHost: serverHost,
    allowOrigins: allowOrigins,
  )) {
    return false;
  }
  return requestOrigin != null && requestOrigin == origin;
}

/// Request model for `/run` and `/run_sse`.
class RunAgentRequest {
  /// Creates a [RunAgentRequest].
  const RunAgentRequest({
    required this.appName,
    required this.userId,
    required this.sessionId,
    this.newMessage,
    this.streaming = false,
    this.stateDelta,
    this.invocationId,
  });

  /// Application name to execute.
  final String appName;

  /// User identifier.
  final String userId;

  /// Session identifier.
  final String sessionId;

  /// Incoming user message content.
  final Map<String, Object?>? newMessage;

  /// Whether partial streaming chunks should be emitted.
  final bool streaming;

  /// Optional session state delta to apply before execution.
  final Map<String, Object?>? stateDelta;

  /// Optional invocation ID to resume or associate.
  final String? invocationId;

  /// Parses a [RunAgentRequest] from JSON.
  factory RunAgentRequest.fromJson(Map<String, Object?> json) {
    return RunAgentRequest(
      appName: '${json['app_name'] ?? json['appName'] ?? ''}',
      userId: '${json['user_id'] ?? json['userId'] ?? ''}',
      sessionId: '${json['session_id'] ?? json['sessionId'] ?? ''}',
      newMessage: (json['new_message'] ?? json['newMessage']) is Map
          ? Map<String, Object?>.from(
              (json['new_message'] ?? json['newMessage']) as Map,
            )
          : null,
      streaming: json['streaming'] as bool? ?? false,
      stateDelta: (json['state_delta'] ?? json['stateDelta']) is Map
          ? Map<String, Object?>.from(
              (json['state_delta'] ?? json['stateDelta']) as Map,
            )
          : null,
      invocationId:
          (json['invocation_id'] ?? json['invocationId']) as String?,
    );
  }

  /// Serializes this request to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'session_id': sessionId,
      if (newMessage != null) 'new_message': newMessage,
      'streaming': streaming,
      if (stateDelta != null) 'state_delta': stateDelta,
      if (invocationId != null) 'invocation_id': invocationId,
    };
  }
}

/// Request model for creating a session.
class CreateSessionRequest {
  /// Creates a [CreateSessionRequest].
  const CreateSessionRequest({
    this.sessionId,
    this.state,
    this.events,
  });

  /// Optional client-provided session ID.
  final String? sessionId;

  /// Optional initial session state map.
  final Map<String, Object?>? state;

  /// Optional initial events list.
  final List<Map<String, Object?>>? events;

  /// Parses a [CreateSessionRequest] from JSON.
  factory CreateSessionRequest.fromJson(Map<String, Object?> json) {
    return CreateSessionRequest(
      sessionId: (json['session_id'] ?? json['sessionId']) as String?,
      state: json['state'] is Map
          ? Map<String, Object?>.from(json['state'] as Map)
          : null,
      events: (json['events'] as List?)
          ?.whereType<Map>()
          .map((Map e) => Map<String, Object?>.from(e))
          .toList(),
    );
  }

  /// Serializes this request to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (sessionId != null) 'session_id': sessionId,
      if (state != null) 'state': state,
      if (events != null) 'events': events,
    };
  }
}

/// Span exporter that stores LLM call trace attributes by event ID.
class ApiServerSpanExporter {
  /// Creates an [ApiServerSpanExporter].
  ApiServerSpanExporter([Map<String, Map<String, Object?>>? traceDict])
    : traceDict = traceDict ?? <String, Map<String, Object?>>{};

  /// Map of `event_id` to exported span data.
  final Map<String, Map<String, Object?>> traceDict;

  /// Exports a list of span maps, retaining `call_llm`, `send_data`, and
  /// `execute_tool` spans that include `gcp.vertex.agent.event_id`.
  void export(List<Map<String, Object?>> spans) {
    for (final Map<String, Object?> span in spans) {
      final String name = '${span['name'] ?? ''}';
      if (name != 'call_llm' &&
          name != 'send_data' &&
          !name.startsWith('execute_tool')) {
        continue;
      }
      final Map<String, Object?> attributes = span['attributes'] is Map
          ? Map<String, Object?>.from(span['attributes'] as Map)
          : <String, Object?>{};
      final String? eventId =
          attributes['gcp.vertex.agent.event_id'] as String?;
      if (eventId == null || eventId.isEmpty) {
        continue;
      }
      traceDict[eventId] = <String, Object?>{
        'name': name,
        'span_id': span['span_id'],
        'trace_id': span['trace_id'],
        'start_time': span['start_time'],
        'end_time': span['end_time'],
        'attributes': attributes,
      };
    }
  }

  /// Clears stored traces.
  void shutdown() {
    traceDict.clear();
  }
}

/// In-memory span exporter retaining session trace spans in memory.
class InMemoryExporter {
  /// Creates an [InMemoryExporter].
  InMemoryExporter([Map<String, Map<String, Object?>>? traceDict])
    : traceDict = traceDict ?? <String, Map<String, Object?>>{};

  /// Shared trace dictionary.
  final Map<String, Map<String, Object?>> traceDict;

  final List<Map<String, Object?>> _spans = <Map<String, Object?>>[];
  final Map<String, Set<String>> _sessionToTraceIds = <String, Set<String>>{};

  /// Exports [spans] into memory and indexes trace IDs by session ID.
  void export(List<Map<String, Object?>> spans) {
    for (final Map<String, Object?> span in spans) {
      _spans.add(span);
      final Map<String, Object?> attributes = span['attributes'] is Map
          ? Map<String, Object?>.from(span['attributes'] as Map)
          : <String, Object?>{};
      final String? sessionId =
          attributes['gcp.vertex.agent.session_id'] as String?;
      final String? traceId = span['trace_id'] as String?;
      if (sessionId != null &&
          sessionId.isNotEmpty &&
          traceId != null &&
          traceId.isNotEmpty) {
        _sessionToTraceIds
            .putIfAbsent(sessionId, () => <String>{})
            .add(traceId);
      }
    }
  }

  /// Returns all spans belonging to traces associated with [sessionId].
  List<Map<String, Object?>> getFinishedSpans(String sessionId) {
    final Set<String>? traceIds = _sessionToTraceIds[sessionId];
    if (traceIds == null || traceIds.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    return _spans
        .where(
          (Map<String, Object?> s) => traceIds.contains('${s['trace_id']}'),
        )
        .toList();
  }

  /// Clears all retained spans.
  void clear() {
    _spans.clear();
    _sessionToTraceIds.clear();
  }
}

/// Production ADK API server (`adk api_server`).
///
/// Serves the core agent execution and session/artifact/memory/A2A endpoints
/// with the Dev UI and internal special agents disabled by default.
class AdkApiServer extends AdkWebServer {
  /// Creates an [AdkApiServer].
  AdkApiServer({
    required super.agentsDir,
    super.appName,
    super.port,
    super.host,
    super.allowOrigins,
    super.sessionServiceUri,
    super.artifactServiceUri,
    super.memoryServiceUri,
    super.evalStorageUri,
    super.useLocalStorage,
    super.urlPrefix,
    super.autoCreateSession,
    super.enableWebUi = false,
    super.logoText,
    super.logoImageUrl,
    super.avatarConfig,
    super.maxLlmCalls,
    super.defaultLlmModel,
    super.reload,
    super.reloadAgents,
    super.traceToCloud,
    super.otelToCloud,
    super.a2a,
    super.extraPlugins,
    super.triggerSources,
    super.triggerOidcAudience,
    super.triggerOidcServiceAccounts,
    super.geminiEnterpriseAppName,
    super.expressMode,
    super.maxLiveMessageBytes,
    super.liveKeepaliveTimeout,
    super.maxLiveSessions,
  });

  /// Whether internal `__*` special agents are allowed on this server.
  bool get allowSpecialAgents => false;

  /// Whether `/debug/trace/*` endpoints are served by this server.
  bool get servesDebugTraceEndpoints => false;
}

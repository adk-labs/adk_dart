/// Production ADK API server and CORS/origin security utilities.
///
/// Mirrors `google.adk.cli.api_server`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Environment variable overriding the Agent Identity Credentials API host.
const String agentIdentityCredentialsTargetHostEnv =
    'AGENT_IDENTITY_CREDENTIALS_TARGET_HOST';

/// Environment variable set by Vertex AI Agent Engine runtimes.
const String googleCloudAgentEngineIdEnv = 'GOOGLE_CLOUD_AGENT_ENGINE_ID';

/// Default production endpoint for the Agent Identity Credentials v1 API.
const String defaultAgentIdentityCredentialsEndpoint =
    'https://agentidentitycredentials.googleapis.com';

/// Request model for `POST /agent-identity/finalize`.
class FinalizeAgentIdentityCredentialsRequest {
  /// Creates a [FinalizeAgentIdentityCredentialsRequest].
  const FinalizeAgentIdentityCredentialsRequest({
    required this.connectorName,
    required this.userId,
    required this.userIdValidationState,
    required this.consentNonce,
  });

  /// Full connector resource name, e.g. `projects/.../connectors/github`.
  final String connectorName;

  /// End-user identity the credential is being stored for.
  final String userId;

  /// URL-safe Base64 validation state returned by the connector redirect.
  final String userIdValidationState;

  /// Single-use nonce from the original consent challenge.
  final String consentNonce;

  /// Parses a [FinalizeAgentIdentityCredentialsRequest] from JSON.
  factory FinalizeAgentIdentityCredentialsRequest.fromJson(
    Map<String, Object?> json,
  ) {
    String readRequiredField(String snakeKey, String camelKey) {
      final Object? value = json.containsKey(snakeKey)
          ? json[snakeKey]
          : json[camelKey];
      if (value is! String) {
        throw FormatException("Field '$snakeKey' is required and must be a string.");
      }
      return value;
    }

    return FinalizeAgentIdentityCredentialsRequest(
      connectorName: readRequiredField('connector_name', 'connectorName'),
      userId: readRequiredField('user_id', 'userId'),
      userIdValidationState: readRequiredField(
        'user_id_validation_state',
        'userIdValidationState',
      ),
      consentNonce: readRequiredField('consent_nonce', 'consentNonce'),
    );
  }

  /// Serializes this request to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'connector_name': connectorName,
      'user_id': userId,
      'user_id_validation_state': userIdValidationState,
      'consent_nonce': consentNonce,
    };
  }
}

/// Request payload sent to `AuthProviderCredentialsService.FinalizeCredentials`.
///
/// Mirrors `google.cloud.agentidentitycredentials_v1.FinalizeCredentialsRequest`.
class FinalizeCredentialsRequest {
  /// Creates a [FinalizeCredentialsRequest].
  const FinalizeCredentialsRequest({
    required this.authProvider,
    required this.userId,
    required this.userIdValidationState,
    required this.consentNonce,
  });

  /// Auth provider resource name (`projects/.../authProviders/...`).
  final String authProvider;

  /// End-user identity for whom credentials are finalized.
  final String userId;

  /// Raw decoded validation state bytes.
  final Uint8List userIdValidationState;

  /// Single-use consent nonce.
  final String consentNonce;
}

/// Exception thrown when Agent Identity support dependencies are unavailable.
class AgentIdentityMissingDependencyException implements Exception {
  /// Creates an [AgentIdentityMissingDependencyException].
  const AgentIdentityMissingDependencyException([
    this.message =
        'Agent Identity support requires: pip install "google-adk[agent-identity]"',
  ]);

  /// Error detail message.
  final String message;

  @override
  String toString() => message;
}

/// Exception thrown when the Agent Identity API rejects request arguments (400).
class AgentIdentityInvalidArgumentException implements Exception {
  /// Creates an [AgentIdentityInvalidArgumentException].
  const AgentIdentityInvalidArgumentException(this.message);

  /// Backend validation error message.
  final String message;

  @override
  String toString() => message;
}

/// Exception thrown when the Agent Identity API call fails with an HTTP/gRPC code.
class AgentIdentityApiException implements Exception {
  /// Creates an [AgentIdentityApiException].
  const AgentIdentityApiException(this.message, {this.code});

  /// Error message returned by the API.
  final String message;

  /// Optional HTTP status code (e.g. `403`, `404`, `503`).
  final int? code;

  @override
  String toString() => message;
}

/// Client interface for the Agent Identity Credentials v1 `AuthProviderCredentialsService`.
abstract interface class AuthProviderCredentialsServiceClient {
  /// Finalizes a 3LO user-consent credential exchange.
  FutureOr<void> finalizeCredentials(FinalizeCredentialsRequest request);
}

/// REST transport implementation of [AuthProviderCredentialsServiceClient].
class RestAuthProviderCredentialsServiceClient
    implements AuthProviderCredentialsServiceClient {
  /// Creates a [RestAuthProviderCredentialsServiceClient].
  RestAuthProviderCredentialsServiceClient({
    String? apiEndpoint,
    HttpClient? httpClient,
    Map<String, String>? environment,
  }) : apiEndpoint = _normalizeEndpoint(
         apiEndpoint ?? defaultAgentIdentityCredentialsEndpoint,
       ),
       _httpClient = httpClient,
       _environment = environment;

  /// Target base endpoint URL (for example `https://agentidentitycredentials.googleapis.com`).
  final String apiEndpoint;
  final HttpClient? _httpClient;
  final Map<String, String>? _environment;

  static String _normalizeEndpoint(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return defaultAgentIdentityCredentialsEndpoint;
    }
    final String withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
            ? trimmed
            : 'https://$trimmed';
    return withScheme.endsWith('/')
        ? withScheme.substring(0, withScheme.length - 1)
        : withScheme;
  }

  @override
  Future<void> finalizeCredentials(FinalizeCredentialsRequest request) async {
    final String resourcePath = request.authProvider.startsWith('/')
        ? request.authProvider.substring(1)
        : request.authProvider;
    final Uri uri = Uri.parse(
      '$apiEndpoint/v1/$resourcePath:finalizeCredentials',
    );
    final HttpClient client = _httpClient ?? HttpClient();
    try {
      final HttpClientRequest httpRequest = await client.postUrl(uri);
      httpRequest.headers.contentType = ContentType.json;
      final Map<String, String> env = _environment ?? Platform.environment;
      final String? bearerToken =
          env['GOOGLE_OAUTH_ACCESS_TOKEN'] ?? env['CLOUD_SDK_ACCESS_TOKEN'];
      if (bearerToken != null && bearerToken.trim().isNotEmpty) {
        httpRequest.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${bearerToken.trim()}',
        );
      }
      httpRequest.write(
        jsonEncode(<String, Object?>{
          'userId': request.userId,
          'userIdValidationState': base64Encode(request.userIdValidationState),
          'consentNonce': request.consentNonce,
        }),
      );
      final HttpClientResponse response = await httpRequest.close();
      final String responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }
      String errorMessage =
          'HTTP ${response.statusCode}: ${responseBody.trim()}';
      try {
        final Object? decoded = jsonDecode(responseBody);
        if (decoded is Map && decoded['error'] is Map) {
          final Map<Object?, Object?> errMap =
              decoded['error'] as Map<Object?, Object?>;
          if (errMap['message'] is String) {
            errorMessage = errMap['message'] as String;
          }
        }
      } on FormatException {
        // Keep raw body message.
      }
      if (response.statusCode == HttpStatus.badRequest) {
        throw AgentIdentityInvalidArgumentException(errorMessage);
      }
      throw AgentIdentityApiException(errorMessage, code: response.statusCode);
    } finally {
      if (_httpClient == null) {
        client.close(force: false);
      }
    }
  }
}

/// Factory signature for creating an [AuthProviderCredentialsServiceClient].
typedef AuthProviderCredentialsClientFactory =
    AuthProviderCredentialsServiceClient Function({
      String? apiEndpoint,
      String transport,
      Map<String, String>? environment,
    });

/// Optional override used by tests to mock `AuthProviderCredentialsServiceClient`.
AuthProviderCredentialsClientFactory?
authProviderCredentialsClientFactoryTestingOverride;

final RegExp _strictUrlSafeBase64RegExp = RegExp(r'^[A-Za-z0-9+/_-]*={0,2}$');

/// Decodes a padded or unpadded URL-safe Base64 `user_id_validation_state`
/// string into raw bytes, throwing a [FormatException] when invalid.
Uint8List decodeUserIdValidationStateBase64(String raw) {
  final int padCount = (4 - (raw.length % 4)) % 4;
  final String padded = '$raw${'=' * padCount}';
  if (!_strictUrlSafeBase64RegExp.hasMatch(padded)) {
    throw const FormatException('Non-base64 digit found');
  }
  final String normalized = padded.replaceAll('-', '+').replaceAll('_', '/');
  return base64Decode(normalized);
}

/// Finalizes Agent Identity 3LO credentials for [request], matching
/// `finalize_agent_identity_credentials` in `google.adk.cli.api_server`.
Future<Map<String, String>> finalizeAgentIdentityCredentials(
  FinalizeAgentIdentityCredentialsRequest request, {
  Map<String, String>? environment,
  AuthProviderCredentialsClientFactory? clientFactory,
}) async {
  final Map<String, String> env = environment ?? Platform.environment;
  final String? targetHost = env[agentIdentityCredentialsTargetHostEnv];
  final String? apiEndpoint = (targetHost != null && targetHost.isNotEmpty)
      ? targetHost
      : null;

  final AuthProviderCredentialsClientFactory resolvedFactory =
      clientFactory ??
      authProviderCredentialsClientFactoryTestingOverride ??
      (({
        String? apiEndpoint,
        String transport = 'rest',
        Map<String, String>? environment,
      }) => RestAuthProviderCredentialsServiceClient(
        apiEndpoint: apiEndpoint,
        environment: environment,
      ));

  final AuthProviderCredentialsServiceClient client = resolvedFactory(
    apiEndpoint: apiEndpoint,
    transport: 'rest',
    environment: env,
  );

  final Uint8List stateBytes;
  try {
    stateBytes = decodeUserIdValidationStateBase64(
      request.userIdValidationState,
    );
  } on FormatException catch (error) {
    throw FormatException(
      'Invalid base64 user_id_validation_state: ${error.message}',
    );
  }

  final FinalizeCredentialsRequest finalizeRequest = FinalizeCredentialsRequest(
    authProvider: request.connectorName.replaceAll(
      '/connectors/',
      '/authProviders/',
    ),
    userId: request.userId,
    userIdValidationState: stateBytes,
    consentNonce: request.consentNonce,
  );

  await client.finalizeCredentials(finalizeRequest);
  return const <String, String>{'status': 'ok'};
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

/// Extracted W3C Trace Context (`traceparent`, `tracestate`) and W3C `baggage`.
class W3cTraceContext {
  /// Creates a [W3cTraceContext].
  const W3cTraceContext({
    this.traceparent,
    this.traceId,
    this.parentSpanId,
    this.traceFlags,
    this.tracestate,
    this.baggage = const <String, String>{},
  });

  /// Raw validated `traceparent` header value, if present and valid.
  final String? traceparent;

  /// 32-hex-character trace ID from `traceparent`, if valid.
  final String? traceId;

  /// 16-hex-character parent span ID from `traceparent`, if valid.
  final String? parentSpanId;

  /// 2-hex-character trace flags from `traceparent`, if valid.
  final String? traceFlags;

  /// Optional W3C `tracestate` header value when `traceparent` is valid.
  final String? tracestate;

  /// Parsed key-value entries from the W3C `baggage` header.
  final Map<String, String> baggage;

  /// Whether a valid `traceparent` was extracted.
  bool get hasTraceContext => traceId != null && parentSpanId != null;

  /// Whether any baggage entries were extracted.
  bool get hasBaggage => baggage.isNotEmpty;
}

final RegExp _traceparentRegex = RegExp(
  r'^([0-9a-f]{2})-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$',
);

/// Returns `true` when native incoming request tracing is enabled for the HTTP
/// server.
///
/// On Vertex AI Agent Engine (`GOOGLE_CLOUD_AGENT_ENGINE_ID` non-empty),
/// incoming `traceparent` headers belong to the platform (often unsampled), so
/// server-level `traceparent` continuation is disabled (`telemetry={"tracing": False}`).
bool isServerTracingEnabled({Map<String, String>? environment}) {
  final String? agentEngineId =
      (environment ?? Platform.environment)[googleCloudAgentEngineIdEnv];
  return agentEngineId == null || agentEngineId.isEmpty;
}

/// Extracts standard W3C Trace Context (`traceparent`, `tracestate`) and
/// W3C `baggage` headers from incoming HTTP [headers] (case-insensitive).
///
/// When [environment] sets a non-empty `GOOGLE_CLOUD_AGENT_ENGINE_ID`,
/// incoming `traceparent` and `tracestate` headers are ignored so unsampled
/// Agent Engine platform spans do not become parent spans or suppress sampling.
///
/// Mirrors `otel.extract(dict(request.headers))` and
/// `FastAPI(..., telemetry={"tracing": not os.getenv("GOOGLE_CLOUD_AGENT_ENGINE_ID")})`
/// in `api_server.py`.
W3cTraceContext extractW3cTraceContext(
  Map<String, String> headers, {
  Map<String, String>? environment,
}) {
  final bool tracingEnabled = isServerTracingEnabled(environment: environment);
  String? rawTraceparent;
  String? rawTracestate;
  String? rawBaggage;

  for (final MapEntry<String, String> entry in headers.entries) {
    final String lowerKey = entry.key.toLowerCase();
    if (lowerKey == 'traceparent') {
      rawTraceparent = entry.value.trim();
    } else if (lowerKey == 'tracestate') {
      rawTracestate = entry.value.trim();
    } else if (lowerKey == 'baggage') {
      rawBaggage = entry.value.trim();
    }
  }

  String? traceparent;
  String? traceId;
  String? parentSpanId;
  String? traceFlags;
  String? tracestate;

  if (tracingEnabled && rawTraceparent != null && rawTraceparent.isNotEmpty) {
    final RegExpMatch? match = _traceparentRegex.firstMatch(rawTraceparent);
    if (match != null) {
      final String version = match.group(1)!;
      final String candidateTraceId = match.group(2)!;
      final String candidateSpanId = match.group(3)!;
      final String candidateFlags = match.group(4)!;
      final bool validVersion = version != 'ff';
      final bool validTraceId = candidateTraceId != '00000000000000000000000000000000';
      final bool validSpanId = candidateSpanId != '0000000000000000';
      if (validVersion && validTraceId && validSpanId) {
        traceparent = rawTraceparent;
        traceId = candidateTraceId;
        parentSpanId = candidateSpanId;
        traceFlags = candidateFlags;
        if (rawTracestate != null && rawTracestate.isNotEmpty) {
          tracestate = rawTracestate;
        }
      }
    }
  }

  final Map<String, String> baggage = <String, String>{};
  if (rawBaggage != null && rawBaggage.isNotEmpty) {
    for (final String member in rawBaggage.split(',')) {
      final String trimmedMember = member.trim();
      if (trimmedMember.isEmpty) {
        continue;
      }
      // Strip optional baggage properties (;prop=val) after the key=value pair.
      final String keyValuePart = trimmedMember.split(';').first.trim();
      final int eqIndex = keyValuePart.indexOf('=');
      if (eqIndex <= 0) {
        continue;
      }
      final String rawKey = keyValuePart.substring(0, eqIndex).trim();
      final String rawVal = keyValuePart.substring(eqIndex + 1).trim();
      if (rawKey.isEmpty) {
        continue;
      }
      String decodedKey = rawKey;
      String decodedVal = rawVal;
      try {
        decodedKey = Uri.decodeComponent(rawKey);
      } on ArgumentError {
        // Keep raw key on malformed percent encoding.
      }
      try {
        decodedVal = Uri.decodeComponent(rawVal);
      } on ArgumentError {
        // Keep raw value on malformed percent encoding.
      }
      baggage[decodedKey] = decodedVal;
    }
  }

  return W3cTraceContext(
    traceparent: traceparent,
    traceId: traceId,
    parentSpanId: parentSpanId,
    traceFlags: traceFlags,
    tracestate: tracestate,
    baggage: baggage,
  );
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
    super.agentLoader,
    super.environment,
    super.evalSetsManager,
    super.evalSetResultsManager,
  });

  /// Telemetry options matching FastAPI's `telemetry` configuration.
  Map<String, Object?> get telemetryConfig => <String, Object?>{
    'tracing': isServerTracingEnabled(environment: environment),
  };

  /// Whether internal `__*` special agents are allowed on this server.
  bool get allowSpecialAgents => false;

  /// Whether `/debug/trace/*` endpoints are served by this server.
  bool get servesDebugTraceEndpoints => false;
}

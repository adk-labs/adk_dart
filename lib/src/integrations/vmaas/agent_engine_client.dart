/// Vertex AI Reasoning Engine / Agent Engine execution client.
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Configuration for connecting to Vertex AI Agent Engine.
class AgentEngineConfig {
  /// Creates an Agent Engine configuration.
  const AgentEngineConfig({
    required this.project,
    required this.location,
    required this.reasoningEngineId,
    this.apiEndpoint,
    this.accessToken,
  });

  /// Google Cloud project ID.
  final String project;

  /// Google Cloud location / region (e.g. `us-central1`).
  final String location;

  /// Reasoning Engine or Agent Engine resource ID.
  final String reasoningEngineId;

  /// Optional override for the Vertex AI API endpoint.
  final String? apiEndpoint;

  /// Optional OAuth2 or service account access token.
  final String? accessToken;

  /// Full resource path to the Reasoning Engine.
  String get reasoningEnginePath =>
      'projects/$project/locations/$location/reasoningEngines/$reasoningEngineId';

  /// Base host endpoint for API requests.
  String get host =>
      apiEndpoint ?? '$location-aiplatform.googleapis.com';
}

/// Configuration for creating or referencing a remote session.
class SessionConfig {
  /// Creates a session configuration.
  const SessionConfig({
    this.userId,
    this.sessionId,
  });

  /// Optional user identifier.
  final String? userId;

  /// Optional session identifier.
  final String? sessionId;

  /// Converts this configuration to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    if (userId != null) 'user_id': userId,
    if (sessionId != null) 'session_id': sessionId,
  };
}

/// Configuration for querying an Agent Engine.
class QueryConfig {
  /// Creates a query configuration.
  const QueryConfig({
    required this.message,
    this.userId,
    this.sessionId,
    this.extra,
  });

  /// Query payload or prompt message.
  final Object? message;

  /// Optional user identifier.
  final String? userId;

  /// Optional session identifier.
  final String? sessionId;

  /// Optional extra fields passed in the request input.
  final Map<String, Object?>? extra;

  /// Converts this configuration to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'message': message,
    if (userId != null) 'user_id': userId,
    if (sessionId != null) 'session_id': sessionId,
    ...?extra,
  };
}

/// Error thrown when an Agent Engine execution fails.
class AgentExecutionError implements Exception {
  /// Creates an agent execution error.
  const AgentExecutionError(this.message, [this.cause]);

  /// Error message.
  final String message;

  /// Underlying cause of the error.
  final Object? cause;

  @override
  String toString() =>
      cause != null ? 'AgentExecutionError: $message (cause: $cause)' : 'AgentExecutionError: $message';
}

/// Client for executing remote queries against Vertex AI Reasoning Engine / Agent Engine.
///
/// ```dart
/// final client = AgentEngineClient(
///   config: AgentEngineConfig(
///     project: 'my-project',
///     location: 'us-central1',
///     reasoningEngineId: '1234567890',
///   ),
/// );
///
/// final response = await client.query(
///   QueryConfig(message: 'What is the stock price of GOOG?'),
/// );
/// ```
class AgentEngineClient {
  /// Creates an Agent Engine client.
  AgentEngineClient({
    required this.config,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Configuration for this client.
  final AgentEngineConfig config;

  final http.Client _httpClient;

  /// Creates a remote session.
  ///
  /// Returns the `create_session` payload returned by the Agent Engine.
  Future<Object?> createSession([SessionConfig config = const SessionConfig()]) async {
    try {
      final response = await _queryReasoningEngine(
        classMethod: 'create_session',
        input: config.toJson(),
      );
      return response['output'];
    } catch (err) {
      if (err is AgentExecutionError) rethrow;
      throw AgentExecutionError('Failed to create session: $err', err);
    }
  }

  /// Executes a single synchronous query against the Agent Engine.
  Future<Object?> query(QueryConfig queryConfig) async {
    try {
      final response = await _queryReasoningEngine(
        classMethod: 'query',
        input: queryConfig.toJson(),
      );
      return response['output'];
    } catch (err) {
      if (err is AgentExecutionError) rethrow;
      throw AgentExecutionError('Failed to execute query: $err', err);
    }
  }

  /// Executes a streaming query against the Agent Engine, returning a stream of parsed JSON fragments.
  Stream<Object?> streamQuery(QueryConfig queryConfig) async* {
    try {
      final request = http.Request(
        'POST',
        Uri.https(config.host, '/v1/${config.reasoningEnginePath}:streamQueryReasoningEngine'),
      );
      request.headers['Content-Type'] = 'application/json';
      if (config.accessToken != null) {
        request.headers['Authorization'] = 'Bearer ${config.accessToken}';
      }
      request.body = jsonEncode(<String, Object?>{
        'class_method': 'query',
        'input': queryConfig.toJson(),
      });

      final streamedResponse = await _httpClient.send(request);
      if (streamedResponse.statusCode >= 400) {
        final body = await streamedResponse.stream.bytesToString();
        throw AgentExecutionError(
          'Failed to execute stream query (status ${streamedResponse.statusCode}): $body',
        );
      }

      String buffer = '';
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final fragment = _parseFragment(line);
          if (fragment != null) {
            yield fragment;
          }
        }
      }

      final last = _parseFragment(buffer);
      if (last != null) {
        yield last;
      }
    } catch (err) {
      if (err is AgentExecutionError) rethrow;
      throw AgentExecutionError('Failed to execute stream query: $err', err);
    }
  }

  Future<Map<String, Object?>> _queryReasoningEngine({
    required String classMethod,
    required Map<String, Object?> input,
  }) async {
    final response = await _httpClient.post(
      Uri.https(config.host, '/v1/${config.reasoningEnginePath}:queryReasoningEngine'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (config.accessToken != null) 'Authorization': 'Bearer ${config.accessToken}',
      },
      body: jsonEncode(<String, Object?>{
        'class_method': classMethod,
        'input': input,
      }),
    );

    if (response.statusCode >= 400) {
      throw AgentExecutionError(
        'Agent Engine returned HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    return <String, Object?>{'output': decoded};
  }

  static Object? _parseFragment(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    final payload = trimmed.startsWith('data:') ? trimmed.substring(5).trim() : trimmed;
    if (payload == '[DONE]') return null;

    try {
      return jsonDecode(payload);
    } catch (e) {
      throw AgentExecutionError('Failed to parse stream fragment: $payload', e);
    }
  }

  /// Closes the underlying HTTP client.
  void close() {
    _httpClient.close();
  }
}

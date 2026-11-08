/// Development ADK web server (`adk web`) and dev-only endpoint models.
///
/// Mirrors `google.adk.cli.dev_server`.
library;

import 'dart:convert';
import 'dart:io';

import 'api_server.dart';

/// Alias for [AdkDevServer].
typedef DevServer = AdkDevServer;

/// Request model for generating a replay test from an existing session.
class CreateTestRequest {
  /// Creates a [CreateTestRequest].
  const CreateTestRequest({
    required this.sessionId,
    required this.userId,
    this.testName,
  });

  /// Source session ID.
  final String sessionId;

  /// User ID owning the session.
  final String userId;

  /// Optional test file basename.
  final String? testName;

  /// Parses a [CreateTestRequest] from JSON.
  factory CreateTestRequest.fromJson(Map<String, Object?> json) {
    return CreateTestRequest(
      sessionId: '${json['session_id'] ?? json['sessionId'] ?? ''}',
      userId: '${json['user_id'] ?? json['userId'] ?? ''}',
      testName: (json['test_name'] ?? json['testName']) as String?,
    );
  }

  /// Serializes this request to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'session_id': sessionId,
      'user_id': userId,
      if (testName != null) 'test_name': testName,
    };
  }
}

/// Request model for adding a session to an evaluation set.
class AddSessionToEvalSetRequest {
  /// Creates an [AddSessionToEvalSetRequest].
  const AddSessionToEvalSetRequest({
    required this.evalId,
    required this.sessionId,
    required this.userId,
  });

  /// Evaluation case identifier.
  final String evalId;

  /// Source session identifier.
  final String sessionId;

  /// User identifier.
  final String userId;

  /// Parses an [AddSessionToEvalSetRequest] from JSON.
  factory AddSessionToEvalSetRequest.fromJson(Map<String, Object?> json) {
    return AddSessionToEvalSetRequest(
      evalId: '${json['eval_id'] ?? json['evalId'] ?? ''}',
      sessionId: '${json['session_id'] ?? json['sessionId'] ?? ''}',
      userId: '${json['user_id'] ?? json['userId'] ?? ''}',
    );
  }

  /// Serializes this request to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'eval_id': evalId,
      'session_id': sessionId,
      'user_id': userId,
    };
  }
}

/// Request model for running an evaluation set.
class RunEvalRequest {
  /// Creates a [RunEvalRequest].
  const RunEvalRequest({
    this.evalIds = const <String>[],
    this.evalMetrics = const <Map<String, Object?>>[],
  });

  /// Specific eval case IDs to execute (empty means all cases in the eval set).
  final List<String> evalIds;

  /// Evaluation metric configurations to compute.
  final List<Map<String, Object?>> evalMetrics;

  /// Parses a [RunEvalRequest] from JSON.
  factory RunEvalRequest.fromJson(Map<String, Object?> json) {
    return RunEvalRequest(
      evalIds: ((json['eval_ids'] ?? json['evalIds']) as List?)
              ?.map((Object? e) => '$e')
              .toList() ??
          const <String>[],
      evalMetrics: ((json['eval_metrics'] ?? json['evalMetrics']) as List?)
              ?.whereType<Map>()
              .map((Map e) => Map<String, Object?>.from(e))
              .toList() ??
          const <Map<String, Object?>>[],
    );
  }

  /// Serializes this request to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'eval_ids': evalIds,
      'eval_metrics': evalMetrics,
    };
  }
}

/// Result of a single evaluation case execution.
class RunEvalResult {
  /// Creates a [RunEvalResult].
  const RunEvalResult({
    required this.evalSetFile,
    required this.evalSetId,
    required this.evalId,
    required this.finalEvalStatus,
    this.evalMetricResults = const <Map<String, Object?>>[],
    this.overallEvalMetricResults = const <Map<String, Object?>>[],
    this.evalMetricResultPerInvocation = const <Map<String, Object?>>[],
    this.userId = 'user',
    this.sessionId = '',
  });

  /// Evaluation set filename or identifier.
  final String evalSetFile;

  /// Evaluation set ID.
  final String evalSetId;

  /// Evaluation case ID.
  final String evalId;

  /// Final evaluation status code or label.
  final Object finalEvalStatus;

  /// Legacy per-metric evaluation results.
  final List<Map<String, Object?>> evalMetricResults;

  /// Overall metric results across the evaluation case.
  final List<Map<String, Object?>> overallEvalMetricResults;

  /// Per-invocation metric results.
  final List<Map<String, Object?>> evalMetricResultPerInvocation;

  /// User ID used during evaluation.
  final String userId;

  /// Session ID created during evaluation.
  final String sessionId;

  /// Serializes this result to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'eval_set_file': evalSetFile,
      'eval_set_id': evalSetId,
      'eval_id': evalId,
      'final_eval_status': finalEvalStatus,
      'eval_metric_results': evalMetricResults,
      'overall_eval_metric_results': overallEvalMetricResults,
      'eval_metric_result_per_invocation': evalMetricResultPerInvocation,
      'user_id': userId,
      'session_id': sessionId,
    };
  }
}

/// Response wrapper containing a list of [RunEvalResult] items.
class RunEvalResponse {
  /// Creates a [RunEvalResponse].
  const RunEvalResponse({this.evalCaseResults = const <RunEvalResult>[]});

  /// Evaluation case results.
  final List<RunEvalResult> evalCaseResults;

  /// Serializes this response to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'eval_case_results': evalCaseResults
          .map((RunEvalResult r) => r.toJson())
          .toList(),
    };
  }
}

/// Result returned by the event graph endpoint (`dotSrc`).
class GetEventGraphResult {
  /// Creates a [GetEventGraphResult].
  const GetEventGraphResult({required this.dotSrc});

  /// Graphviz DOT source string.
  final String dotSrc;

  /// Serializes this result to a JSON map.
  Map<String, Object?> toJson() => <String, Object?>{'dot_src': dotSrc, 'dotSrc': dotSrc};
}

/// Request model for creating a new evaluation set.
class CreateEvalSetRequest {
  /// Creates a [CreateEvalSetRequest].
  const CreateEvalSetRequest({required this.evalSet});

  /// Evaluation set payload.
  final Map<String, Object?> evalSet;

  /// Serializes this request to a JSON map.
  Map<String, Object?> toJson() => <String, Object?>{'eval_set': evalSet};
}

/// Response model listing evaluation set IDs.
class ListEvalSetsResponse {
  /// Creates a [ListEvalSetsResponse].
  const ListEvalSetsResponse({this.evalSetIds = const <String>[]});

  /// Evaluation set identifiers.
  final List<String> evalSetIds;

  /// Serializes this response to a JSON map.
  Map<String, Object?> toJson() => <String, Object?>{'eval_set_ids': evalSetIds};
}

/// Alias for an evaluation set result payload in the Dev server.
typedef EvalResult = Map<String, Object?>;

/// Response model listing evaluation result IDs.
class ListEvalResultsResponse {
  /// Creates a [ListEvalResultsResponse].
  const ListEvalResultsResponse({this.evalResultIds = const <String>[]});

  /// Evaluation result identifiers.
  final List<String> evalResultIds;

  /// Serializes this response to a JSON map.
  Map<String, Object?> toJson() =>
      <String, Object?>{'eval_result_ids': evalResultIds};
}

/// Response model listing registered evaluation metric definitions.
class ListMetricsInfoResponse {
  /// Creates a [ListMetricsInfoResponse].
  const ListMetricsInfoResponse({
    this.metricsInfo = const <Map<String, Object?>>[],
  });

  /// Registered metrics metadata list.
  final List<Map<String, Object?>> metricsInfo;

  /// Serializes this response to a JSON map.
  Map<String, Object?> toJson() => <String, Object?>{'metrics_info': metricsInfo};
}

/// Request model for `POST /config/telemetry`.
class TelemetryConsentRequest {
  /// Creates a [TelemetryConsentRequest].
  const TelemetryConsentRequest({required this.telemetry});

  /// Whether telemetry collection is enabled.
  final bool telemetry;

  /// Parses a [TelemetryConsentRequest] from JSON.
  factory TelemetryConsentRequest.fromJson(Map<String, Object?> json) {
    final Object? val = json['telemetry'];
    if (val is! bool) {
      throw const FormatException("'telemetry' boolean field is required");
    }
    return TelemetryConsentRequest(telemetry: val);
  }

  /// Serializes this request to a JSON map.
  Map<String, Object?> toJson() => <String, Object?>{'telemetry': telemetry};
}

/// Verifies that an agent-builder or dev-deploy client is local or explicitly
/// permitted by `ADK_ALLOW_REMOTE_AGENT_BUILDER`, throwing a [StateError] when
/// access should be rejected with HTTP 403.
void requireLocalAgentBuilderClient({
  required bool isLocal,
  Map<String, String>? environment,
  bool hasForeignOrigin = false,
}) {
  if (hasForeignOrigin) {
    throw StateError(
      "This endpoint writes agent files or starts runs, so it accepts "
      "browser requests only from this server's own origin or an origin "
      "listed literally in allow_origins.",
    );
  }
  final Map<String, String> env = environment ?? Platform.environment;
  final String allowRemote =
      (env['ADK_ALLOW_REMOTE_AGENT_BUILDER'] ?? '').trim().toLowerCase();
  if (allowRemote == '1' || allowRemote == 'true' || allowRemote == 'yes') {
    return;
  }
  if (!isLocal) {
    throw StateError(
      'Agent builder and dev deploy endpoints are restricted to local loopback '
      'clients unless ADK_ALLOW_REMOTE_AGENT_BUILDER=1 is set.',
    );
  }
}

/// Recursively inspects a parsed YAML/JSON structure and throws an
/// [ArgumentError] if any `code` reference key is present (preventing arbitrary
/// code execution from untrusted YAML definitions).
void checkCodeReference(Object? value) {
  if (value is Map) {
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if ('${entry.key}' == 'code') {
        throw ArgumentError(
          'Arbitrary code references ("code") are not allowed in visual builder YAML.',
        );
      }
      checkCodeReference(entry.value);
    }
  } else if (value is List) {
    for (final Object? item in value) {
      checkCodeReference(item);
    }
  }
}

/// Streams combined stdout and stderr lines from a test runner [process].
Stream<String> streamTestOutput(Process process) async* {
  final Stream<String> stdoutLines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final Stream<String> stderrLines = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final String line in stdoutLines) {
    yield '$line\n';
  }
  await for (final String line in stderrLines) {
    yield '$line\n';
  }
}

/// Development ADK web server (`adk web`).
///
/// Extends [AdkApiServer] with the browser-based Dev UI, evaluation routes,
/// trace inspection endpoints, agent-builder endpoints, and `/dev/apps/.../deploy/*`
/// routes enabled.
class AdkDevServer extends AdkApiServer {
  /// Creates an [AdkDevServer].
  AdkDevServer({
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
    super.enableWebUi = true,
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
    super.evalSetsManager,
    super.evalSetResultsManager,
  });

  @override
  bool get allowSpecialAgents => enableWebUi && isLoopbackAddress(host);

  @override
  bool get servesDebugTraceEndpoints => true;
}

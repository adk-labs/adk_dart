/// Client label helpers used to populate API telemetry headers.
library;

import 'dart:async';

import 'system_environment/system_environment.dart';
import '../version.dart';

const String _adkLabel = 'google-adk';
const String _languageLabel = 'gl-dart';
const String _agentEngineTelemetryTag = 'remote_reasoning_engine';
const String _agentEngineTelemetryEnvVariableName =
    'GOOGLE_CLOUD_AGENT_ENGINE_ID';
const String _cloudRunTelemetryTag = 'cloud_run';
const List<String> _cloudRunTelemetryEnvVariableNames = <String>[
  'K_SERVICE',
  'CLOUD_RUN_JOB',
];
const String _k8sTelemetryTag = 'k8s';
const String _k8sTelemetryEnvVariableName = 'KUBERNETES_SERVICE_HOST';
const Object _labelContextKey = Object();

/// Environment variables that select a hosting runtime telemetry tag.
const List<String> runtimeTelemetryEnvVariableNames = <String>[
  _agentEngineTelemetryEnvVariableName,
  ..._cloudRunTelemetryEnvVariableNames,
  _k8sTelemetryEnvVariableName,
];

/// The default client label used by evaluation API calls.
const String evalClientLabel = 'google-adk-eval/$adkVersion';

/// Label used to denote advisor LLM calls made by ModelConsultTool.
const String modelConsultClientLabel = 'google-adk-model-consult/$adkVersion';

/// Label used to denote reasoning LLM calls made by CascadeLive.
const String cascadeLiveClientLabel = 'google-adk-cascade-live/$adkVersion';

/// Returns the label for calls made by a classifier, such as `"llm"`.
String classifierClientLabel(String kind) {
  return 'google-adk-classifier/$adkVersion+$kind';
}

String? _detectRuntimeTag(Map<String, String> env) {
  if ((env[_agentEngineTelemetryEnvVariableName] ?? '').isNotEmpty) {
    return _agentEngineTelemetryTag;
  }
  for (final String name in _cloudRunTelemetryEnvVariableNames) {
    if ((env[name] ?? '').isNotEmpty) {
      return _cloudRunTelemetryTag;
    }
  }
  if ((env[_k8sTelemetryEnvVariableName] ?? '').isNotEmpty) {
    return _k8sTelemetryTag;
  }
  return null;
}

List<String> _getDefaultLabels({
  String? frameworkLabel,
  bool excludeRuntimeTag = false,
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? readSystemEnvironment();
  String frameworkToken = '$_adkLabel/$adkVersion';
  if (frameworkLabel != null && frameworkLabel.isNotEmpty) {
    frameworkToken = '$frameworkToken+$frameworkLabel';
  } else if (!excludeRuntimeTag) {
    final String? runtimeTag = _detectRuntimeTag(env);
    if (runtimeTag != null) {
      frameworkToken = '$frameworkToken+$runtimeTag';
    }
  }

  final String languageVersion = readRuntimeLanguageVersion();
  final String languageLabel = '$_languageLabel/$languageVersion';
  return <String>[frameworkToken, languageLabel];
}

/// Runs [operation] with a temporary custom [clientLabel] bound to this zone.
///
/// Throws an [ArgumentError] when a custom label already exists in the current
/// zone scope.
T clientLabelContext<T>(String clientLabel, T Function() operation) {
  final String? currentClientLabel = Zone.current[_labelContextKey] as String?;
  if (currentClientLabel != null) {
    throw ArgumentError(
      'Client label already exists. You can only add one client label.',
    );
  }
  return runZoned(
    operation,
    zoneValues: <Object?, Object?>{_labelContextKey: clientLabel},
  );
}

/// The client labels for request headers in the current execution context.
///
/// This always includes framework and language labels, and appends the
/// zone-scoped custom label when [clientLabelContext] was used.
List<String> getClientLabels({
  String? frameworkLabel,
  bool excludeRuntimeTag = false,
  Map<String, String>? environment,
}) {
  final List<String> labels = _getDefaultLabels(
    frameworkLabel: frameworkLabel,
    excludeRuntimeTag: excludeRuntimeTag,
    environment: environment,
  );
  final String? currentClientLabel = Zone.current[_labelContextKey] as String?;
  if (currentClientLabel != null && currentClientLabel.isNotEmpty) {
    labels.add(currentClientLabel);
  }
  return labels;
}

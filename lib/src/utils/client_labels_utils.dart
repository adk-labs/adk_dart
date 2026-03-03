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
const Object _labelContextKey = Object();

/// The default client label used by evaluation API calls.
const String evalClientLabel = 'google-adk-eval/$adkVersion';

List<String> _getDefaultLabels({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? readSystemEnvironment();
  String frameworkLabel = '$_adkLabel/$adkVersion';
  if ((env[_agentEngineTelemetryEnvVariableName] ?? '').isNotEmpty) {
    frameworkLabel = '$frameworkLabel+$_agentEngineTelemetryTag';
  }

  final String languageVersion = readRuntimeLanguageVersion();
  final String languageLabel = '$_languageLabel/$languageVersion';
  return <String>[frameworkLabel, languageLabel];
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
List<String> getClientLabels({Map<String, String>? environment}) {
  final List<String> labels = _getDefaultLabels(environment: environment);
  final String? currentClientLabel = Zone.current[_labelContextKey] as String?;
  if (currentClientLabel != null && currentClientLabel.isNotEmpty) {
    labels.add(currentClientLabel);
  }
  return labels;
}

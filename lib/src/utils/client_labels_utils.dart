import 'dart:async';

import 'system_environment/system_environment.dart';
import '../version.dart';

const String _adkLabel = 'google-adk';
const String _languageLabel = 'gl-dart';
const String _agentEngineTelemetryTag = 'remote_reasoning_engine';
const String _agentEngineTelemetryEnvVariableName =
    'GOOGLE_CLOUD_AGENT_ENGINE_ID';
const Object _labelContextKey = Object();

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

List<String> getClientLabels({Map<String, String>? environment}) {
  final List<String> labels = _getDefaultLabels(environment: environment);
  final String? currentClientLabel = Zone.current[_labelContextKey] as String?;
  if (currentClientLabel != null && currentClientLabel.isNotEmpty) {
    labels.add(currentClientLabel);
  }
  return labels;
}

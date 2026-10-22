/// Environment variable parsing helpers.
library;

import 'system_environment/system_environment.dart';

const Set<String> _truthyEnvValues = <String>{'1', 'true', 'yes', 'on'};
const Set<String> _strictTruthyEnvValues = <String>{'1', 'true'};

/// Environment variable name that suppresses experimental feature warnings.
const String experimentalWarningSuppressionEnvVar =
    'ADK_SUPPRESS_EXPERIMENTAL_FEATURE_WARNINGS';

/// Whether experimental feature warnings are suppressed in [environment].
bool isExperimentalWarningSuppressed({Map<String, String>? environment}) =>
    isEnvEnabled(
      experimentalWarningSuppressionEnvVar,
      environment: environment,
    );

/// Whether [envVarName] is enabled in [environment].
///
/// Values `1`, `true`, `yes`, and `on` are treated as enabled after trimming
/// and lowercase conversion.
bool isEnvEnabled(
  String envVarName, {
  String defaultValue = '0',
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? readSystemEnvironment();
  final String value = (env[envVarName] ?? defaultValue).trim().toLowerCase();
  return _truthyEnvValues.contains(value);
}

/// Check if a google-genai boolean environment variable is enabled.
///
/// Matches google-genai's BaseApiClient strict parsing (`envStr.toLowerCase() in
/// ['true', '1']` without stripping whitespace or accepting `'yes'`/`'on'`).
bool _isGenaiEnvEnabled(
  String envVarName, {
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? readSystemEnvironment();
  final String value = (env[envVarName] ?? '').toLowerCase();
  return _strictTruthyEnvValues.contains(value);
}

/// Check if Google GenAI Enterprise mode is enabled via environment variables.
bool isEnterpriseModeEnabled({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? readSystemEnvironment();
  if (env.containsKey('GOOGLE_GENAI_USE_ENTERPRISE')) {
    return _isGenaiEnvEnabled(
      'GOOGLE_GENAI_USE_ENTERPRISE',
      environment: environment,
    );
  }
  if (env.containsKey('GOOGLE_GENAI_USE_VERTEXAI')) {
    return _isGenaiEnvEnabled('GOOGLE_GENAI_USE_VERTEXAI', environment: environment);
  }
  return false;
}

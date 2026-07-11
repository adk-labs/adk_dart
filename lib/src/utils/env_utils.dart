/// Environment variable parsing helpers.
library;

import 'system_environment/system_environment.dart';

/// Whether [envVarName] is enabled in [environment].
///
/// Values `true` and `1` are treated as enabled after lowercase conversion.
bool isEnvEnabled(
  String envVarName, {
  String defaultValue = '0',
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? readSystemEnvironment();
  final String value = (env[envVarName] ?? defaultValue).toLowerCase();
  return value == 'true' || value == '1';
}

/// Check if Google GenAI Enterprise mode is enabled via environment variables.
bool isEnterpriseModeEnabled({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? readSystemEnvironment();
  if (env.containsKey('GOOGLE_GENAI_USE_ENTERPRISE')) {
    return isEnvEnabled('GOOGLE_GENAI_USE_ENTERPRISE', environment: environment);
  }
  if (env.containsKey('GOOGLE_GENAI_USE_VERTEXAI')) {
    return isEnvEnabled('GOOGLE_GENAI_USE_VERTEXAI', environment: environment);
  }
  return false;
}

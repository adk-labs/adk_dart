import 'dart:io';

bool isEnvEnabled(
  String envVarName, {
  String defaultValue = '0',
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String value = (env[envVarName] ?? defaultValue).toLowerCase();
  return value == 'true' || value == '1';
}

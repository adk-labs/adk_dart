import 'system_environment/system_environment.dart';

bool isEnvEnabled(
  String envVarName, {
  String defaultValue = '0',
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? readSystemEnvironment();
  final String value = (env[envVarName] ?? defaultValue).toLowerCase();
  return value == 'true' || value == '1';
}

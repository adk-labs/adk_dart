import 'dart:io';

import 'env_utils.dart';

String? getExpressModeApiKey({
  String? project,
  String? location,
  String? expressModeApiKey,
  Map<String, String>? environment,
}) {
  if ((project != null || location != null) && expressModeApiKey != null) {
    throw ArgumentError(
      'Cannot specify project or location and express_mode_api_key. '
      'Either use project and location, or just the express_mode_api_key.',
    );
  }

  if (!isEnvEnabled('GOOGLE_GENAI_USE_VERTEXAI', environment: environment)) {
    return null;
  }

  if (expressModeApiKey != null && expressModeApiKey.isNotEmpty) {
    return expressModeApiKey;
  }

  final Map<String, String> env = environment ?? Platform.environment;
  return env['GOOGLE_API_KEY'];
}

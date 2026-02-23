import 'env_utils.dart';

const String _disableGeminiModelIdCheckEnvVar =
    'ADK_DISABLE_GEMINI_MODEL_ID_CHECK';

bool isGeminiModelIdCheckDisabled({Map<String, String>? environment}) {
  return isEnvEnabled(
    _disableGeminiModelIdCheckEnvVar,
    environment: environment,
  );
}

String extractModelName(String modelString) {
  final RegExp vertexPath = RegExp(
    r'^projects/[^/]+/locations/[^/]+/publishers/[^/]+/models/(.+)$',
  );
  final RegExp apigeePath = RegExp(r'^apigee/(?:[^/]+/)?(?:[^/]+/)?(.+)$');

  for (final RegExp pattern in <RegExp>[vertexPath, apigeePath]) {
    final RegExpMatch? match = pattern.firstMatch(modelString);
    if (match != null) {
      return match.group(1) ?? modelString;
    }
  }

  if (modelString.startsWith('models/')) {
    return modelString.substring('models/'.length);
  }

  return modelString;
}

bool isGeminiModel(String? modelString) {
  if (modelString == null || modelString.isEmpty) {
    return false;
  }
  return extractModelName(modelString).startsWith('gemini-');
}

bool isGemini1Model(String? modelString) {
  if (modelString == null || modelString.isEmpty) {
    return false;
  }
  return RegExp(r'^gemini-1\.\d+').hasMatch(extractModelName(modelString));
}

bool isGemini2OrAbove(String? modelString) {
  if (modelString == null || modelString.isEmpty) {
    return false;
  }

  final String modelName = extractModelName(modelString);
  if (!modelName.startsWith('gemini-')) {
    return false;
  }

  final String remainder = modelName.substring('gemini-'.length);
  if (remainder.isEmpty) {
    return false;
  }
  final String versionToken = remainder.split('-').first;
  if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(versionToken)) {
    return false;
  }
  final int major = int.parse(versionToken.split('.').first);
  return major >= 2;
}

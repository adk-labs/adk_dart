/// Model-name normalization helpers for Google model identifiers.
library;

import '../models/llm_request.dart';
import 'env_utils.dart';

const String _disableGeminiModelIdCheckEnvVar =
    'ADK_DISABLE_GEMINI_MODEL_ID_CHECK';

/// Whether Gemini model ID validation is disabled by environment override.
bool isGeminiModelIdCheckDisabled({Map<String, String>? environment}) {
  return isEnvEnabled(
    _disableGeminiModelIdCheckEnvVar,
    environment: environment,
  );
}

/// The canonical model name extracted from [modelString].
///
/// This strips known Vertex AI, Apigee, and `models/` path prefixes.
String extractModelName(String modelString) {
  final RegExp vertexPath = RegExp(
    r'^(?:projects/[^/]+/locations/[^/]+/)?publishers/[^/]+/models/(.+)$',
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

/// Whether [modelString] represents a Gemini model.
bool isGeminiModel(String? modelString) {
  if (modelString == null || modelString.isEmpty) {
    return false;
  }
  return extractModelName(modelString).startsWith('gemini-');
}

/// Whether [modelString] represents a Gemini 1.x model.
bool isGemini1Model(String? modelString) {
  if (modelString == null || modelString.isEmpty) {
    return false;
  }
  return RegExp(r'^gemini-1\.\d+').hasMatch(extractModelName(modelString));
}

/// Returns the numeric major version of a Gemini [modelString], or `null`.
int? geminiMajorVersion(String? modelString) {
  if (modelString == null || modelString.isEmpty || !isGeminiModel(modelString)) {
    return null;
  }
  final String modelName = extractModelName(modelString);
  final String remainder = modelName.substring('gemini-'.length);
  if (remainder.isEmpty) {
    return null;
  }
  final String versionToken = remainder.split('-').first;
  if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(versionToken)) {
    return null;
  }
  return int.tryParse(versionToken.split('.').first);
}

/// Whether [modelString] names a Gemini 3.0 or later model.
bool isGemini3OrNewer(String? modelString) {
  final int? major = geminiMajorVersion(modelString);
  return major != null && major >= 3;
}

/// Replaces the default thinking budget with [thinkingLevel] on Gemini 4+.
///
/// Returns [config] itself unless [model] is Gemini 4 or later and
/// `config.thinkingConfig` still equals [defaultThinkingConfig], in which case
/// it returns a copy that sets `thinking_level` instead of `thinking_budget`.
GenerateContentConfig withGemini4ThinkingLevel(
  GenerateContentConfig config, {
  required String? model,
  required Map<String, Object?> defaultThinkingConfig,
  required String thinkingLevel,
}) {
  final int? major = geminiMajorVersion(model);
  if (major == null || major < 4) {
    return config;
  }
  if (!_thinkingConfigsEqual(config.thinkingConfig, defaultThinkingConfig)) {
    return config;
  }
  final Object? includeThoughts =
      defaultThinkingConfig['include_thoughts'] ??
      defaultThinkingConfig['includeThoughts'];
  return config.copyWith(
    thinkingConfig: <String, Object?>{
      'include_thoughts': ?includeThoughts,
      'thinking_level': thinkingLevel,
    },
  );
}

bool _thinkingConfigsEqual(
  Object? actual,
  Map<String, Object?> expected,
) {
  if (actual is! Map) {
    return false;
  }
  if (actual.length != expected.length) {
    return false;
  }
  for (final MapEntry<String, Object?> entry in expected.entries) {
    if (!actual.containsKey(entry.key) || actual[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// Whether [modelString] represents Gemini EAP or Gemini major version 2+.
bool isGeminiEapOr2OrAbove(String? modelString) {
  if (modelString == null || modelString.isEmpty) {
    return false;
  }

  final String modelName = extractModelName(modelString);
  if (_isGeminiEapModelName(modelName)) {
    return true;
  }
  final int? major = geminiMajorVersion(modelString);
  return major != null && major >= 2;
}

/// Whether [modelString] represents Gemini major version 2 or later.
bool isGemini2OrAbove(String? modelString) {
  final int? major = geminiMajorVersion(modelString);
  return major != null && major >= 2;
}

/// Whether [modelString] supports combining built-in search tools with
/// function calling (Gemini 3+).
bool supportsBuiltinToolsWithFunctionCalling(String? modelString) {
  return isGemini3OrNewer(modelString);
}

bool _isGeminiEapModelName(String modelName) {
  return RegExp(
    r'^gemini-(?:[a-z0-9_]+(?:-[a-z0-9_]+)*-)?early-exp\d*$',
  ).hasMatch(modelName);
}

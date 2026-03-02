/// CLI environment loading and override helpers.
library;

import 'dart:collection';
import 'dart:io';

import '../../utils/env_utils.dart';

/// Environment variable key that disables `.env` loading for CLI runs.
const String adkDisableLoadDotenvEnvVar = 'ADK_DISABLE_LOAD_DOTENV';

final Set<String> _explicitEnvKeys = Set<String>.from(
  Platform.environment.keys,
);
final Map<String, String> _loadedEnv = <String, String>{};

/// Returns an immutable view of effective CLI environment values.
UnmodifiableMapView<String, String> getCliEnvironment() {
  return UnmodifiableMapView<String, String>(<String, String>{
    ...Platform.environment,
    ..._loadedEnv,
  });
}

/// Looks up one environment [key] from CLI overrides and process environment.
String? getCliEnvironmentValue(String key) {
  return _loadedEnv[key] ?? Platform.environment[key];
}

/// Sets one CLI environment override [key] to [value].
void setCliEnvironmentValue(String key, String value) {
  _loadedEnv[key] = value;
}

/// Adds multiple CLI environment overrides from [values].
void setCliEnvironmentValues(Map<String, String> values) {
  _loadedEnv.addAll(values);
}

/// Clears all CLI environment overrides.
void clearCliEnvironmentOverrides() {
  _loadedEnv.clear();
}

/// Walks upward from [folder] until [filename] is found.
///
/// Returns `null` when no matching file exists up to the filesystem root.
File? walkToRootUntilFound(String folder, String filename) {
  final Directory current = Directory(folder).absolute;
  final File candidate = File(
    '${current.path}${Platform.pathSeparator}$filename',
  );
  if (candidate.existsSync()) {
    return candidate;
  }

  final Directory parent = current.parent.absolute;
  if (parent.path == current.path) {
    return null;
  }
  return walkToRootUntilFound(parent.path, filename);
}

/// Loads dotenv variables for [agentName] from [agentParentFolder].
///
/// Existing process environment variables are preserved.
void loadDotenvForAgent(
  String agentName,
  String agentParentFolder, {
  String filename = '.env',
  void Function(String message)? log,
}) {
  if (isEnvEnabled(
    adkDisableLoadDotenvEnvVar,
    environment: getCliEnvironment(),
  )) {
    log?.call(
      'Skipping $filename loading because $adkDisableLoadDotenvEnvVar is enabled.',
    );
    return;
  }

  final String startingFolder = Directory(
    '$agentParentFolder${Platform.pathSeparator}$agentName',
  ).absolute.path;
  final File? dotenv = walkToRootUntilFound(startingFolder, filename);
  if (dotenv == null) {
    log?.call('No $filename file found for $agentName');
    return;
  }

  final Map<String, String> loaded = _parseDotenv(dotenv.readAsLinesSync());
  for (final MapEntry<String, String> entry in loaded.entries) {
    if (_explicitEnvKeys.contains(entry.key) &&
        Platform.environment.containsKey(entry.key)) {
      continue;
    }
    _loadedEnv[entry.key] = entry.value;
  }

  log?.call('Loaded $filename file for $agentName at ${dotenv.path}');
}

Map<String, String> _parseDotenv(List<String> lines) {
  final Map<String, String> values = <String, String>{};
  for (final String rawLine in lines) {
    final String line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final int split = line.indexOf('=');
    if (split <= 0) {
      continue;
    }
    final String key = line.substring(0, split).trim();
    if (key.isEmpty) {
      continue;
    }
    String value = line.substring(split + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    values[key] = value;
  }
  return values;
}

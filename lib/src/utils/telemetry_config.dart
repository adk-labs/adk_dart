/// Telemetry user consent configuration utilities.
library;

import 'dart:convert';
import 'dart:io';

/// Returns the path to the ADK global config file (`~/.adk/config.json`).
File getUserConfigFile() {
  final String home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  final String separator = Platform.pathSeparator;
  return File('$home$separator.adk${separator}config.json');
}

/// Reads the telemetry consent status from local config (`config.json`).
///
/// Returns `true` if opted-in, `false` if opted-out, and `null` if no explicit
/// preference has been recorded yet.
bool? readTelemetryConsent({File? configFile}) {
  final File file = configFile ?? getUserConfigFile();
  if (!file.existsSync()) {
    return null;
  }
  try {
    final String content = file.readAsStringSync();
    final Object? decoded = jsonDecode(content);
    if (decoded is Map && decoded['telemetry'] is bool) {
      return decoded['telemetry'] as bool;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Writes the telemetry consent status to local config (`config.json`).
void writeTelemetryConsent(bool enabled, {File? configFile}) {
  final File file = configFile ?? getUserConfigFile();
  try {
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    Map<String, Object?> config = <String, Object?>{};
    if (file.existsSync()) {
      try {
        final Object? decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, Object?>) {
          config = Map<String, Object?>.from(decoded);
        } else if (decoded is Map) {
          config = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        config = <String, Object?>{};
      }
    }
    config['telemetry'] = enabled;
    file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(config)}\n');
  } catch (e) {
    rethrow;
  }
}

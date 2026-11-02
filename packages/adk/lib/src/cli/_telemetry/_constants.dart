/// Constants for CLI telemetry storage and file locking.
library;

import 'dart:io';

String _resolveHomeDir() {
  final String? home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.isNotEmpty) {
    return home;
  }
  return Directory.current.path;
}

String _joinPath(List<String> parts) => parts.join(Platform.pathSeparator);

/// Path to the lock file used to synchronize telemetry queue operations.
final String lockFile = _joinPath(<String>[
  _resolveHomeDir(),
  '.adk',
  'metrics_queue.lock',
]);

/// Path to the file where unsent telemetry metric payloads are queued.
final String queueFile = _joinPath(<String>[
  _resolveHomeDir(),
  '.adk',
  'metrics_queue.jsonl',
]);

/// Directory where per-session telemetry state files are stored.
final String telemetrySessionsDir = _joinPath(<String>[
  _resolveHomeDir(),
  '.adk',
  'telemetry_sessions',
]);

/// Alias matching the Python constant name `LOCK_FILE`.
// ignore: non_constant_identifier_names
String get LOCK_FILE => lockFile;

/// Alias matching the Python constant name `QUEUE_FILE`.
// ignore: non_constant_identifier_names
String get QUEUE_FILE => queueFile;

/// Alias matching the Python constant name `TELEMETRY_SESSIONS_DIR`.
// ignore: non_constant_identifier_names
String get TELEMETRY_SESSIONS_DIR => telemetrySessionsDir;

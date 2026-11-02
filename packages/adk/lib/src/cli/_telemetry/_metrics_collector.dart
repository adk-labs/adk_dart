/// Telemetry metrics collector for CLI commands and web server endpoints.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../version.dart';
import '_constants.dart';
import '_metrics_reporter.dart';

/// Default expiration window for telemetry session state in seconds (30 mins).
const int sessionExpirationSeconds = 1800;

/// Prunes expired telemetry session files from [sessionsDir].
void pruneExpiredSessions({
  String? sessionsDir,
  double? nowSeconds,
  int expirationSeconds = sessionExpirationSeconds,
}) {
  final String targetDir = sessionsDir ?? telemetrySessionsDir;
  final Directory dir = Directory(targetDir);
  if (!dir.existsSync()) {
    return;
  }
  final double currentTime =
      nowSeconds ?? DateTime.now().millisecondsSinceEpoch / 1000.0;
  try {
    for (final FileSystemEntity entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      try {
        final String content = entity.readAsStringSync();
        final Object? decoded = jsonDecode(content);
        if (decoded is Map) {
          final Object? lastActive = decoded['last_active'];
          final double? lastActiveSec = lastActive is num
              ? lastActive.toDouble()
              : double.tryParse('$lastActive');
          if (lastActiveSec == null ||
              currentTime - lastActiveSec > expirationSeconds) {
            entity.deleteSync();
          }
        }
      } catch (_) {
        try {
          entity.deleteSync();
        } catch (_) {}
      }
    }
  } catch (_) {}
}

/// Loads or initializes the telemetry session state for [sessionKey].
///
/// Returns a map containing `session_id` (String) and `last_active` (double).
Map<String, Object?> loadSessionState(
  String sessionKey, {
  String? sessionsDir,
  double? nowSeconds,
  int expirationSeconds = sessionExpirationSeconds,
}) {
  final String targetDir = sessionsDir ?? telemetrySessionsDir;
  final Directory dir = Directory(targetDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  pruneExpiredSessions(
    sessionsDir: targetDir,
    nowSeconds: nowSeconds,
    expirationSeconds: expirationSeconds,
  );

  final String safeKey = sessionKey.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final File stateFile = File(
    '$targetDir${Platform.pathSeparator}$safeKey.json',
  );
  final double currentTime =
      nowSeconds ?? DateTime.now().millisecondsSinceEpoch / 1000.0;

  if (stateFile.existsSync()) {
    try {
      final Object? decoded = jsonDecode(stateFile.readAsStringSync());
      if (decoded is Map) {
        final String? sessionId = decoded['session_id'] as String?;
        final Object? lastActive = decoded['last_active'];
        final double? lastActiveSec = lastActive is num
            ? lastActive.toDouble()
            : double.tryParse('$lastActive');
        if (sessionId != null &&
            sessionId.isNotEmpty &&
            lastActiveSec != null &&
            currentTime - lastActiveSec <= expirationSeconds) {
          final Map<String, Object?> updated = <String, Object?>{
            'session_id': sessionId,
            'last_active': currentTime,
          };
          writeSessionState(sessionKey, updated, sessionsDir: targetDir);
          return updated;
        }
      }
    } catch (_) {}
  }

  final Map<String, Object?> created = <String, Object?>{
    'session_id': _generateUuidV4(),
    'last_active': currentTime,
  };
  writeSessionState(sessionKey, created, sessionsDir: targetDir);
  return created;
}

/// Writes the telemetry [state] for [sessionKey] to disk.
void writeSessionState(
  String sessionKey,
  Map<String, Object?> state, {
  String? sessionsDir,
}) {
  final String targetDir = sessionsDir ?? telemetrySessionsDir;
  final Directory dir = Directory(targetDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final String safeKey = sessionKey.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final File stateFile = File(
    '$targetDir${Platform.pathSeparator}$safeKey.json',
  );
  try {
    stateFile.writeAsStringSync(jsonEncode(state));
  } catch (_) {}
}

String _generateUuidV4() {
  final Random random = Random();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
  return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
      '${hex(bytes[4])}${hex(bytes[5])}-'
      '${hex(bytes[6])}${hex(bytes[7])}-'
      '${hex(bytes[8])}${hex(bytes[9])}-'
      '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}'
      '${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
}

/// Collects and queues CLI and web server telemetry metrics.
class MetricsCollector {
  /// Creates a [MetricsCollector].
  MetricsCollector({
    this.userId,
    this.installationId,
    this.adkVersion = adkPackageVersion,
    this.pythonVersion,
    this.osName,
    this.osVersion,
    this.machineArch,
    String? queueFilePath,
    String? sessionsDirPath,
  }) : _queueFilePath = queueFilePath ?? queueFile,
       _sessionsDirPath = sessionsDirPath ?? telemetrySessionsDir;

  /// Optional user identifier.
  final String? userId;

  /// Optional installation identifier.
  final String? installationId;

  /// ADK SDK version string.
  final String adkVersion;

  /// Runtime / language version string.
  final String? pythonVersion;

  /// Operating system name.
  final String? osName;

  /// Operating system version.
  final String? osVersion;

  /// Machine architecture.
  final String? machineArch;

  final String _queueFilePath;
  final String _sessionsDirPath;

  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];

  /// Returns an unmodifiable view of collected in-memory events.
  List<Map<String, Object?>> get events =>
      List<Map<String, Object?>>.unmodifiable(_events);

  /// Records a CLI command execution event.
  Map<String, Object?> recordCliCommand({
    required String commandName,
    List<String> flags = const <String>[],
    int exitCode = 0,
    int? durationMs,
    String? errorType,
    String sessionKey = 'cli',
  }) {
    final Map<String, Object?> session = loadSessionState(
      sessionKey,
      sessionsDir: _sessionsDirPath,
    );
    final Map<String, Object?> payload = <String, Object?>{
      'event_type': 'cli_command',
      'command_name': commandName,
      'flags': flags,
      'exit_code': exitCode,
      'duration_ms': ?durationMs,
      'error_type': ?errorType,
      'session_id': session['session_id'],
      'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
      ..._systemMetadata(),
    };
    _appendEvent(payload);
    return payload;
  }

  /// Records a web server HTTP endpoint invocation event.
  Map<String, Object?> recordHttpEndpoint({
    required String method,
    required String path,
    required int statusCode,
    int? durationMs,
    String sessionKey = 'web',
  }) {
    final Map<String, Object?> session = loadSessionState(
      sessionKey,
      sessionsDir: _sessionsDirPath,
    );
    final Map<String, Object?> payload = <String, Object?>{
      'event_type': 'http_endpoint',
      'http_method': method,
      'http_path': path,
      'status_code': statusCode,
      'duration_ms': ?durationMs,
      'session_id': session['session_id'],
      'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
      ..._systemMetadata(),
    };
    _appendEvent(payload);
    return payload;
  }

  /// Flushes queued metrics using [reportMetrics].
  Future<bool> flush({
    String? endpointUrl,
    Future<HttpReportResult> Function(String url, String body)? transport,
  }) async {
    return reportMetrics(
      queueFilePath: _queueFilePath,
      endpointUrl: endpointUrl,
      transport: transport,
    );
  }

  Map<String, Object?> _systemMetadata() {
    return <String, Object?>{
      'adk_version': adkVersion,
      'runtime_version': pythonVersion ?? Platform.version.split(' ').first,
      'os_name': osName ?? Platform.operatingSystem,
      'os_version': osVersion ?? Platform.operatingSystemVersion,
      'machine_arch': ?machineArch,
      'user_id': ?userId,
      'installation_id': ?installationId,
    };
  }

  void _appendEvent(Map<String, Object?> event) {
    _events.add(event);
    try {
      final File file = File(_queueFilePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('${jsonEncode(event)}\n', mode: FileMode.append);
    } catch (_) {}
  }
}

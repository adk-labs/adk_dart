/// Logging setup helpers used by CLI tooling and tests.
library;

import 'dart:io';

/// Default Python-style logging format string retained for parity.
const String loggingFormat =
    '%(asctime)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s';

/// Active logger configuration for CLI log setup.
class AdkLoggerConfig {
  /// Creates logger configuration with an optional [level].
  AdkLoggerConfig({this.level = Level.info});

  /// Minimum level written by the logger.
  final Level level;
}

/// Supported log levels for CLI logging setup.
enum Level { debug, info, warning, error }

/// Sets the process-wide ADK logger configuration.
void setupAdkLogger({Level level = Level.info}) {
  // Dart's standard logging does not have a process-wide formatter equivalent
  // to Python logging.basicConfig. This function is kept as a parity surface.
  _activeLoggerConfig = AdkLoggerConfig(level: level);
}

AdkLoggerConfig _activeLoggerConfig = AdkLoggerConfig();

/// The currently active logger configuration.
AdkLoggerConfig get activeLoggerConfig => _activeLoggerConfig;

/// Creates or replaces a symbolic link from [symlinkPath] to [targetPath].
///
/// Returns `false` when the existing path is not a symlink or creation fails.
bool createSymlink(String symlinkPath, String targetPath) {
  final Link link = Link(symlinkPath);
  final FileSystemEntityType type = FileSystemEntity.typeSync(
    symlinkPath,
    followLinks: false,
  );
  if (type == FileSystemEntityType.link) {
    link.deleteSync();
  } else if (type != FileSystemEntityType.notFound) {
    return false;
  }

  try {
    link.createSync(targetPath, recursive: true);
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Creates a stable `latest` symlink for a log file when possible.
void tryCreateLatestLogSymlink(
  String logDir,
  String logFilePrefix,
  String logFilePath, {
  void Function(String message)? echo,
}) {
  final String latestLink =
      '$logDir${Platform.pathSeparator}$logFilePrefix.latest.log';
  if (createSymlink(latestLink, logFilePath)) {
    (echo ?? print)('To access latest log: tail -F $latestLink');
  } else {
    (echo ?? print)('To access latest log: tail -F $logFilePath');
  }
}

/// Initializes a temporary log file and returns its path.
String logToTmpFolder({
  Level level = Level.info,
  String subFolder = 'agents_log',
  String logFilePrefix = 'agent',
  String? logFileTimestamp,
  void Function(String message)? echo,
}) {
  setupAdkLogger(level: level);
  final String timestamp =
      logFileTimestamp ??
      DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:\-]'), '');

  final Directory dir = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}$subFolder',
  );
  dir.createSync(recursive: true);

  final String filename = '$logFilePrefix.$timestamp.log';
  final File logFile = File('${dir.path}${Platform.pathSeparator}$filename');
  logFile.writeAsStringSync('');

  (echo ?? print)('Log setup complete: ${logFile.path}');
  tryCreateLatestLogSymlink(dir.path, logFilePrefix, logFile.path, echo: echo);
  return logFile.path;
}

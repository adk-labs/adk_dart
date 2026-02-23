import 'dart:io';

const String loggingFormat =
    '%(asctime)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s';

class AdkLoggerConfig {
  AdkLoggerConfig({this.level = Level.info});

  final Level level;
}

enum Level { debug, info, warning, error }

void setupAdkLogger({Level level = Level.info}) {
  // Dart's standard logging does not have a process-wide formatter equivalent
  // to Python logging.basicConfig. This function is kept as a parity surface.
  _activeLoggerConfig = AdkLoggerConfig(level: level);
}

AdkLoggerConfig _activeLoggerConfig = AdkLoggerConfig();

AdkLoggerConfig get activeLoggerConfig => _activeLoggerConfig;

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

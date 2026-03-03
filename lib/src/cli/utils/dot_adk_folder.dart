/// Helpers for reading and writing `.adk` workspace directories.
library;

import 'dart:io';

/// Coerces [value] to an absolute [Directory].
///
/// The [value] can be a [Directory] or a string path.
Directory directoryFromArg(Object value, {required String parameterName}) {
  if (value is Directory) {
    return value.absolute;
  }
  if (value is String) {
    return Directory(value).absolute;
  }
  throw ArgumentError.value(
    value,
    parameterName,
    'must be a String path or Directory',
  );
}

String _ensureTrailingSlash(String path) {
  return path.endsWith('/') ? path : '$path/';
}

Directory _resolveAgentDir({
  required Object agentsRoot,
  required String appName,
}) {
  final Directory agentsRootDir = directoryFromArg(
    agentsRoot,
    parameterName: 'agentsRoot',
  );
  final String rootPath = _ensureTrailingSlash(agentsRootDir.uri.path);
  final Directory agentDir = Directory(
    '${agentsRootDir.path}${Platform.pathSeparator}$appName',
  ).absolute;
  final String agentPath = _ensureTrailingSlash(agentDir.uri.path);

  if (!agentPath.startsWith(rootPath)) {
    throw ArgumentError.value(
      appName,
      'appName',
      'resolves outside base directory',
    );
  }

  return agentDir;
}

/// Helper for reading and writing files under the `.adk` folder.
class DotAdkFolder {
  /// Creates a `.adk` folder helper scoped to [agentDir].
  DotAdkFolder(Object agentDir)
    : _agentDir = directoryFromArg(agentDir, parameterName: 'agentDir');

  final Directory _agentDir;

  /// The absolute agent directory this helper points to.
  Directory get agentDir => _agentDir;

  /// The `.adk` directory under [agentDir].
  Directory get dotAdkDir =>
      Directory('${_agentDir.path}${Platform.pathSeparator}.adk');

  /// The artifacts directory under `.adk`.
  Directory get artifactsDir =>
      Directory('${dotAdkDir.path}${Platform.pathSeparator}artifacts');

  /// The SQLite session database path under `.adk`.
  File get sessionDbPath =>
      File('${dotAdkDir.path}${Platform.pathSeparator}session.db');
}

/// Returns a [DotAdkFolder] resolved from [agentsRoot] and [appName].
DotAdkFolder dotAdkFolderForAgent({
  required Object agentsRoot,
  required String appName,
}) {
  return DotAdkFolder(
    _resolveAgentDir(agentsRoot: agentsRoot, appName: appName),
  );
}

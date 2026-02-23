import 'dart:io';

Directory _resolveAgentDir({
  required Object agentsRoot,
  required String appName,
}) {
  final Directory agentsRootDir = Directory('$agentsRoot').absolute;
  final String rootPath = agentsRootDir.uri.path;
  final Directory agentDir = Directory(
    '${agentsRootDir.path}${Platform.pathSeparator}$appName',
  ).absolute;

  if (!agentDir.uri.path.startsWith(rootPath)) {
    throw ArgumentError.value(
      appName,
      'appName',
      'resolves outside base directory',
    );
  }

  return agentDir;
}

class DotAdkFolder {
  DotAdkFolder(Object agentDir) : _agentDir = Directory('$agentDir').absolute;

  final Directory _agentDir;

  Directory get agentDir => _agentDir;

  Directory get dotAdkDir =>
      Directory('${_agentDir.path}${Platform.pathSeparator}.adk');

  Directory get artifactsDir =>
      Directory('${dotAdkDir.path}${Platform.pathSeparator}artifacts');

  File get sessionDbPath =>
      File('${dotAdkDir.path}${Platform.pathSeparator}session.db');
}

DotAdkFolder dotAdkFolderForAgent({
  required Object agentsRoot,
  required String appName,
}) {
  return DotAdkFolder(
    _resolveAgentDir(agentsRoot: agentsRoot, appName: appName),
  );
}

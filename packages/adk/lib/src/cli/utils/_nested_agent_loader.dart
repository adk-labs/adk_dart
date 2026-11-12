/// Recursive nested directory agent loader for ADK CLI dev environments.
library;

import 'dart:io';

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/config_agent_utils.dart'
    as config_agent_utils;
import '../../dev/project.dart' show DevProjectConfig, projectDirName;
import '../../dev/runtime.dart';
import 'agent_loader.dart';
import 'base_agent_loader.dart';
import 'envs.dart';

/// Subclass of [AgentLoader] that supports recursive nested directory discovery
/// and dot-nested namespaces for dev environments.
class NestedAgentLoader extends AgentLoader {
  static final RegExp _identifierPartRegExp = RegExp(
    r'^[a-zA-Z_][a-zA-Z0-9_]*$',
  );

  /// Creates a [NestedAgentLoader] rooted at [agentsDir].
  NestedAgentLoader(
    super.agentsDir, {
    super.agentFactories,
    super.enableDevProjectFallback,
  }) {
    _initAgentMode(agentsDir);
  }

  /// Returns `true` if [path] is a valid single-agent directory.
  static bool isValidAgentDir(Object path) {
    return isSingleAgentDirectory(path);
  }

  /// Returns `true` if there are any nested agents within [agentsPath] (up to max depth 5).
  bool hasNestedAgents(Object agentsPath) {
    final Directory rootDir = _toDirectory(agentsPath);
    if (!rootDir.existsSync()) {
      return false;
    }
    return _scanNestedAgents(rootDir, rootDir, depth: 0, maxDepth: 5);
  }

  bool _scanNestedAgents(
    Directory rootDir,
    Directory currentDir, {
    required int depth,
    required int maxDepth,
  }) {
    if (currentDir.path != rootDir.path && isValidAgentDir(currentDir)) {
      return true;
    }
    if (depth >= maxDepth) {
      return false;
    }

    final List<FileSystemEntity> entries;
    try {
      entries = currentDir.listSync(followLinks: false);
    } on FileSystemException {
      return false;
    }

    for (final FileSystemEntity entity in entries) {
      if (entity is! Directory) {
        continue;
      }
      final String name = _basename(entity.path);
      if (name.isEmpty ||
          name.startsWith('.') ||
          name == '__pycache__' ||
          name == 'tmp') {
        continue;
      }
      if (_scanNestedAgents(
        rootDir,
        entity,
        depth: depth + 1,
        maxDepth: maxDepth,
      )) {
        return true;
      }
    }
    return false;
  }

  void _initAgentMode(String rawPath) {
    final File candidateFile = File(rawPath).absolute;
    bool isFile = false;
    try {
      isFile =
          candidateFile.existsSync() &&
          FileSystemEntity.typeSync(candidateFile.path) ==
              FileSystemEntityType.file;
    } on Object {
      isFile = false;
    }

    if (isFile) {
      final String fileName = _basename(candidateFile.path);
      final int dotIndex = fileName.lastIndexOf('.');
      final String stem = dotIndex > 0
          ? fileName.substring(0, dotIndex)
          : fileName;
      configureAgentMode(
        isSingleAgent: true,
        singleAgentName: stem,
        agentsDir: candidateFile.parent.path,
      );
      return;
    }

    final Directory agentsPath = Directory(rawPath).absolute;
    if (isValidAgentDir(agentsPath)) {
      final String resolvedName =
          singleRootConfiguredAlias(agentsPath) ??
          projectDirName(agentsPath.path);
      configureAgentMode(
        isSingleAgent: true,
        singleAgentName: resolvedName,
        agentsDir: agentsPath.parent.path,
      );
    } else {
      configureAgentMode(
        isSingleAgent: false,
        singleAgentName: null,
        agentsDir: agentsPath.path,
      );
    }
  }

  /// Lists all agents recursively across subdirectories (sorted alphabetically).
  @override
  List<String> listAgents() {
    if (isSingleAgent) {
      final String? singleName = singleAgentName;
      return singleName == null ? <String>[] : <String>[singleName];
    }

    final Directory basePath = Directory(agentsDir).absolute;
    try {
      if (!basePath.existsSync()) {
        return <String>[];
      }
    } on Object {
      return <String>[];
    }

    final List<String> apps = <String>[];
    _collectNestedAgents(basePath, basePath, apps: apps, depth: 0, maxDepth: 5);
    apps.sort();
    return apps;
  }

  void _collectNestedAgents(
    Directory basePath,
    Directory currentDir, {
    required List<String> apps,
    required int depth,
    required int maxDepth,
  }) {
    if (currentDir.path != basePath.path && isValidAgentDir(currentDir)) {
      final String relPath = _relativePath(basePath.path, currentDir.path);
      if (relPath.isNotEmpty && relPath != '.') {
        apps.add(relPath.replaceAll('\\', '.').replaceAll('/', '.'));
      }
    }

    if (depth >= maxDepth) {
      return;
    }

    final List<FileSystemEntity> children;
    try {
      children = currentDir.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }

    for (final FileSystemEntity entity in children) {
      if (entity is! Directory) {
        continue;
      }
      final String dirName = _basename(entity.path);
      if (dirName.isEmpty ||
          dirName.startsWith('.') ||
          dirName == '__pycache__' ||
          dirName == 'tmp') {
        continue;
      }
      _collectNestedAgents(
        basePath,
        entity,
        apps: apps,
        depth: depth + 1,
        maxDepth: maxDepth,
      );
    }
  }

  /// Validates [fullAgentName], allowing dot-separated or slash-separated paths.
  void validateAgentName(String fullAgentName) {
    final String agentRelativePath;
    final String checkDir;
    if (fullAgentName.startsWith('__')) {
      if (!allowSpecialAgents) {
        throw StateError(
          "Loading special internal agent '$fullAgentName' is disabled in "
          'this loader configuration.',
        );
      }
      agentRelativePath = fullAgentName.substring(2);
      checkDir = Directory(specialAgentsDir).absolute.path;
    } else {
      agentRelativePath = fullAgentName;
      checkDir = agentsDir;
    }

    if (isSingleAgent && !fullAgentName.startsWith('__')) {
      if (fullAgentName != singleAgentName) {
        throw ArgumentError.value(
          fullAgentName,
          'fullAgentName',
          "Agent not found: '$fullAgentName'. In single agent mode, only "
              "'$singleAgentName' is accessible.",
        );
      }
    }

    final String normalizedPath = agentRelativePath.replaceAll('.', '/');
    final List<String> parts = normalizedPath.split('/');
    for (final String part in parts) {
      if (part.isEmpty ||
          part.contains('\n') ||
          part.contains('\r') ||
          !_identifierPartRegExp.hasMatch(part)) {
        throw ArgumentError.value(
          fullAgentName,
          'fullAgentName',
          "Invalid agent name: '$fullAgentName'. Agent names must be valid "
              'identifiers or paths separated by dots (letters, digits, '
              'underscores, and dots).',
        );
      }
    }

    final String sep = Platform.pathSeparator;
    final String fsRelPath = parts.join(sep);
    final Directory agentPath = Directory('$checkDir$sep$fsRelPath');
    final File agentPyFile = File('$checkDir$sep$fsRelPath.py');
    final File agentDartFile = File('$checkDir$sep$fsRelPath.dart');
    if (!(agentPath.existsSync() ||
        agentPyFile.existsSync() ||
        agentDartFile.existsSync())) {
      throw ArgumentError.value(
        fullAgentName,
        'fullAgentName',
        "Agent not found: '$fullAgentName'. No matching directory or module "
            "exists in '$checkDir$sep$fsRelPath'.",
      );
    }
  }

  /// Loads an agent module (with caching & `.env`) and returns its root agent,
  /// workflow node, or app.
  @override
  AgentOrApp loadAgent(String agentName) {
    final AgentOrApp? cached = agentCache[agentName];
    if (cached != null) {
      return cached;
    }

    final AgentOrApp loaded = performLoad(agentName);
    agentCache[agentName] = loaded;
    return loaded;
  }

  @override
  AgentOrApp performLoad(String agentName) {
    final AgentFactory? customFactory = agentFactories[agentName];
    if (customFactory != null) {
      final AgentOrApp created = customFactory(agentName, agentsDir);
      recordOriginMetadata(
        loaded: created,
        expectedAppName: agentName,
        agentsDir: agentsDir,
      );
      return created;
    }

    validateAgentName(agentName);

    final String effectiveAgentsDir;
    final String actualAgentName;
    if (agentName.startsWith('__')) {
      effectiveAgentsDir = Directory(specialAgentsDir).absolute.path;
      actualAgentName = agentName.substring(2);
    } else {
      effectiveAgentsDir = agentsDir;
      actualAgentName = agentName.replaceAll('.', '/');
    }

    final String sep = Platform.pathSeparator;
    final String fsRelPath = actualAgentName.replaceAll('/', sep);
    loadDotenvForAgent(fsRelPath, effectiveAgentsDir);

    final Directory agentDir = Directory('$effectiveAgentsDir$sep$fsRelPath');
    final File rootAgentYaml = File('${agentDir.path}${sep}root_agent.yaml');
    if (rootAgentYaml.existsSync()) {
      final BaseAgent loaded = config_agent_utils.fromConfig(
        rootAgentYaml.path,
      );
      recordOriginMetadata(
        loaded: loaded,
        expectedAppName: actualAgentName,
        agentsDir: effectiveAgentsDir,
        originDirOverride: agentDir,
      );
      return loaded;
    }

    final File adkJson = File('${agentDir.path}${sep}adk.json');
    final File agentDart = File('${agentDir.path}${sep}agent.dart');
    if (enableDevProjectFallback &&
        (adkJson.existsSync() || agentDart.existsSync())) {
      final DevProjectConfig config = loadDevProjectConfigSync(agentDir.path);
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      final BaseAgent loaded = runtime.runner.agent;
      recordOriginMetadata(
        loaded: loaded,
        expectedAppName: agentName,
        agentsDir: effectiveAgentsDir,
        originDirOverride: agentDir,
      );
      return loaded;
    }

    String hint = '';
    final Directory rootPath = Directory(effectiveAgentsDir);
    if (File('${rootPath.path}${sep}agent.py').existsSync() ||
        File('${rootPath.path}${sep}agent.dart').existsSync() ||
        File('${rootPath.path}${sep}root_agent.yaml').existsSync()) {
      hint =
          '\n\nHINT: It looks like this command might be running from inside an '
          'agent directory. Run it from the parent directory that contains '
          'your agent folder (for example the project root) so the loader can '
          'locate your agents.';
    }

    throw ArgumentError(
      "No root_agent found for '$agentName'. Searched in "
      "'$actualAgentName.agent.root_agent', '$actualAgentName.root_agent' and "
      "'$actualAgentName${sep}root_agent.yaml'.\n\nExpected directory "
      'structure:\n  <agents_dir>$sep\n    $actualAgentName$sep\n      '
      'agent.py (with root_agent) OR\n      root_agent.yaml\n\nThen run: adk '
      "web <agents_dir>\n\nEnsure '$effectiveAgentsDir$sep$fsRelPath' is "
      'structured correctly, an .env file can be loaded if present, and a '
      'root_agent is exposed.$hint',
    );
  }

  @override
  String determineAgentLanguage(String agentName) {
    final String sep = Platform.pathSeparator;
    final String relPath = agentName.replaceAll('.', sep).replaceAll('/', sep);
    final Directory basePath = Directory('$agentsDir$sep$relPath');

    if (File('${basePath.path}${sep}root_agent.yaml').existsSync()) {
      return 'yaml';
    }
    if (File('${basePath.path}${sep}agent.dart').existsSync() ||
        File('${basePath.path}${sep}adk.json').existsSync()) {
      return 'dart';
    }
    if (File('${basePath.path}${sep}agent.py').existsSync() ||
        (File('${basePath.path}$sep' '__init__.py').existsSync() &&
            isValidAgentDir(basePath))) {
      return 'python';
    }

    throw ArgumentError("Could not determine agent type for '$agentName'.");
  }

  @override
  void removeAgentFromCache(String agentName) {
    final String agentDotPath = agentName.replaceAll('/', '.');
    final List<String> keysToDelete = agentCache.keys
        .where(
          (String key) =>
              key == agentName ||
              key == agentDotPath ||
              key.startsWith('$agentDotPath.'),
        )
        .toList(growable: false);
    for (final String key in keysToDelete) {
      agentCache.remove(key);
    }
  }
}

Directory _toDirectory(Object path) {
  if (path is Directory) {
    return path.absolute;
  }
  if (path is FileSystemEntity) {
    return Directory(path.path).absolute;
  }
  return Directory('$path').absolute;
}

String _basename(String path) {
  final String normalized = path.replaceAll('\\', '/');
  final List<String> segments = normalized
      .split('/')
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  return segments.isEmpty ? '' : segments.last;
}

String _relativePath(String rootPath, String targetPath) {
  String normRoot = Directory(rootPath).absolute.path.replaceAll('\\', '/');
  final String normTarget = Directory(
    targetPath,
  ).absolute.path.replaceAll('\\', '/');
  if (!normRoot.endsWith('/')) {
    normRoot = '$normRoot/';
  }
  if (normTarget == normRoot.substring(0, normRoot.length - 1)) {
    return '.';
  }
  if (normTarget.startsWith(normRoot)) {
    return normTarget.substring(normRoot.length);
  }
  return normTarget;
}

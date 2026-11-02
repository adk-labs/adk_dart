/// Filesystem-backed loader for CLI agent and app discovery.
library;

import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/config_agent_utils.dart'
    as config_agent_utils;
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/base_toolset.dart';
import 'package:adk_dart/src/tools/computer_use/computer_use_toolset.dart';
import 'package:adk_dart/src/tools/function_tool.dart';
import '../../dev/project.dart' show DevProjectConfig, projectDirName;
import '../../dev/runtime.dart';
import 'base_agent_loader.dart';
import 'envs.dart';

/// Factory signature used to resolve an agent at runtime.
typedef AgentFactory = AgentOrApp Function(String agentName, String agentsDir);

/// Returns `true` if [path] is a directory containing a single agent definition.
///
/// Accepts a [String] path or a [Directory] / [FileSystemEntity].
bool isSingleAgentDirectory(Object path) {
  try {
    final Directory dir;
    if (path is Directory) {
      dir = path.absolute;
    } else if (path is FileSystemEntity) {
      dir = Directory(path.path).absolute;
    } else if (path is String) {
      dir = Directory(path).absolute;
    } else {
      return false;
    }
    if (!dir.existsSync()) {
      return false;
    }
    final String base = dir.path;
    final String sep = Platform.pathSeparator;
    return File('$base${sep}agent.py').existsSync() ||
        File('$base${sep}agent.dart').existsSync() ||
        File('$base${sep}adk.json').existsSync() ||
        File('$base${sep}root_agent.yaml').existsSync();
  } on Object {
    return false;
  }
}

/// Directory path used for built-in special agents prefixed with `__`.
final String specialAgentsDir = Directory(
  '${Directory.current.path}${Platform.pathSeparator}built_in_agents',
).path;

/// Filesystem-backed loader for ADK agents and apps.
class AgentLoader extends BaseAgentLoader {
  static final RegExp _validAgentNameRegExp = RegExp(r'^[a-zA-Z0-9_]+$');

  /// Creates a loader rooted at [agentsDir].
  ///
  /// When [enableDevProjectFallback] is true, directories containing only
  /// `adk.json` or `agent.dart` are loaded through the dev runtime fallback.
  AgentLoader(
    this.agentsDir, {
    Map<String, AgentFactory>? agentFactories,
    bool enableDevProjectFallback = true,
  }) : _agentFactories = agentFactories ?? <String, AgentFactory>{},
       _enableDevProjectFallback = enableDevProjectFallback;

  /// Root directory that contains loadable agents.
  String agentsDir;
  bool? _forcedSingleAgent;
  String? _forcedSingleAgentName;
  final Map<String, AgentFactory> _agentFactories;
  final bool _enableDevProjectFallback;
  final Map<String, AgentOrApp> _agentCache = <String, AgentOrApp>{};

  /// Custom agent factories registered with this loader.
  Map<String, AgentFactory> get agentFactories => _agentFactories;

  /// Whether the dev project fallback is enabled.
  bool get enableDevProjectFallback => _enableDevProjectFallback;

  /// In-memory cache of loaded agents and apps.
  Map<String, AgentOrApp> get agentCache => _agentCache;

  /// Returns `true` if the loader is in single-agent mode.
  bool get isSingleAgent {
    if (_forcedSingleAgent != null) {
      return _forcedSingleAgent!;
    }
    return _isSingleAppRoot(Directory(agentsDir).absolute);
  }

  /// Returns the name of the agent when in single-agent mode, or `null`.
  String? get singleAgentName {
    if (_forcedSingleAgent != null) {
      return _forcedSingleAgentName;
    }
    final Directory base = Directory(agentsDir).absolute;
    if (_isSingleAppRoot(base)) {
      return _singleRootAgentName(base);
    }
    return null;
  }

  /// Forces single-agent mode with [name] and [agentsDir].
  void setSingleAgentMode(String name, String agentsDir) {
    _forcedSingleAgent = true;
    _forcedSingleAgentName = name;
    this.agentsDir = agentsDir;
  }

  /// Configures single-agent vs multi-agent mode manually for subclasses.
  void configureAgentMode({
    required bool isSingleAgent,
    required String? singleAgentName,
    required String agentsDir,
  }) {
    _forcedSingleAgent = isSingleAgent;
    _forcedSingleAgentName = singleAgentName;
    this.agentsDir = agentsDir;
  }

  /// Returns `true` if [dir] looks like a loadable agent directory.
  static bool looksLikeAgentDir(Directory dir) {
    try {
      final String sep = Platform.pathSeparator;
      return isSingleAgentDirectory(dir) ||
          File('${dir.path}$sep' '__init__.py').existsSync();
    } on Object {
      return false;
    }
  }

  /// Loads [agentName] and caches the result for subsequent lookups.
  @override
  AgentOrApp loadAgent(String agentName) {
    final AgentOrApp? cached = _agentCache[agentName];
    if (cached != null) {
      return cached;
    }

    final AgentOrApp loaded = performLoad(agentName);
    _agentCache[agentName] = loaded;
    return loaded;
  }

  /// Internal logic to load an agent by [agentName].
  AgentOrApp performLoad(String agentName) {
    final AgentFactory? customFactory = _agentFactories[agentName];
    if (customFactory != null) {
      final AgentOrApp created = customFactory(agentName, agentsDir);
      recordOriginMetadata(
        loaded: created,
        expectedAppName: agentName,
        agentsDir: agentsDir,
      );
      return created;
    }

    final _ResolvedAgentTarget target = _resolveAgentTarget(agentName);

    loadDotenvForAgent(target.normalizedName, target.agentParentForEnv);

    final File rootAgentYaml = File(
      '${target.agentDir.path}${Platform.pathSeparator}root_agent.yaml',
    );
    if (rootAgentYaml.existsSync()) {
      final BaseAgent loaded = config_agent_utils.fromConfig(
        rootAgentYaml.path,
      );
      recordOriginMetadata(
        loaded: loaded,
        expectedAppName: agentName,
        agentsDir: target.agentParentForEnv,
        originDirOverride: target.agentDir,
      );
      return loaded;
    }

    final File adkJson = File(
      '${target.agentDir.path}${Platform.pathSeparator}adk.json',
    );
    final File agentDart = File(
      '${target.agentDir.path}${Platform.pathSeparator}agent.dart',
    );
    if (_enableDevProjectFallback &&
        (adkJson.existsSync() || agentDart.existsSync())) {
      final DevProjectConfig config = loadDevProjectConfigSync(
        target.agentDir.path,
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      final BaseAgent loaded = runtime.runner.agent;
      recordOriginMetadata(
        loaded: loaded,
        expectedAppName: agentName,
        agentsDir: target.agentParentForEnv,
        originDirOverride: target.agentDir,
      );
      return loaded;
    }

    throw StateError(
      "No root agent found for '$agentName'. Expected either "
      "'${target.normalizedName}/root_agent.yaml' or "
      "'${target.normalizedName}/agent.dart' under $agentsDir.",
    );
  }

  /// Annotates [loaded] with its origin app name and directory path.
  void recordOriginMetadata({
    required AgentOrApp loaded,
    required String expectedAppName,
    required String agentsDir,
    Directory? originDirOverride,
  }) {
    if (expectedAppName.startsWith('__')) {
      return;
    }
    final Directory candidate =
        originDirOverride ??
        Directory(
          '$agentsDir${Platform.pathSeparator}${expectedAppName.replaceAll('.', Platform.pathSeparator)}',
        ).absolute;
    final Directory originPath = candidate.existsSync()
        ? candidate
        : Directory(agentsDir).absolute;
    attachAgentOriginMetadata(
      loaded: loaded,
      expectedAppName: expectedAppName,
      originPath: originPath,
    );
  }

  /// All visible agent directory names under [agentsDir].
  @override
  List<String> listAgents() {
    if (_forcedSingleAgent == true) {
      final String? singleName = _forcedSingleAgentName;
      return (singleName == null || singleName.isEmpty)
          ? <String>[]
          : <String>[singleName];
    }

    final Directory base = Directory(agentsDir).absolute;
    if (!base.existsSync()) {
      return <String>[];
    }

    if (_forcedSingleAgent == null && _isSingleAppRoot(base)) {
      final String singleRootName = _singleRootAgentName(base);
      return singleRootName.isEmpty ? <String>[] : <String>[singleRootName];
    }

    final List<String> names = <String>[];
    for (final FileSystemEntity entity in base.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final String name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments[entity.uri.pathSegments.length - 2];
      if (name.isEmpty || name.startsWith('.') || name == '__pycache__') {
        continue;
      }
      names.add(name);
    }
    names.sort();
    return names;
  }

  /// Detailed metadata for all loadable agents.
  ///
  /// Entries that fail to load are skipped to preserve Python CLI parity.
  @override
  List<Map<String, Object?>> listAgentsDetailed() {
    final List<Map<String, Object?>> appsInfo = <Map<String, Object?>>[];
    for (final String agentName in listAgents()) {
      try {
        final AgentOrApp loaded = loadAgent(agentName);
        final BaseAgent root = asBaseAgent(loaded);
        final String language = determineAgentLanguage(agentName);
        final bool isComputerUse = isComputerUseAgent(root);
        appsInfo.add(<String, Object?>{
          'name': agentName,
          'root_agent_name': root.name,
          'description': root.description,
          'language': language,
          'is_computer_use': isComputerUse,
        });
      } catch (_) {
        // Keep parity behavior with Python loader: skip failed entries.
      }
    }
    return appsInfo;
  }

  /// Determines the implementation language (`yaml`, `dart`, or `python`) for [agentName].
  String determineAgentLanguage(String agentName) {
    final Directory basePath = _resolveAgentTarget(agentName).agentDir;

    if (File(
      '${basePath.path}${Platform.pathSeparator}root_agent.yaml',
    ).existsSync()) {
      return 'yaml';
    }
    if (File(
          '${basePath.path}${Platform.pathSeparator}agent.dart',
        ).existsSync() ||
        File(
          '${basePath.path}${Platform.pathSeparator}adk.json',
        ).existsSync()) {
      return 'dart';
    }
    if (File(
          '${basePath.path}${Platform.pathSeparator}agent.py',
        ).existsSync() ||
        File(
          '${basePath.path}${Platform.pathSeparator}__init__.py',
        ).existsSync()) {
      return 'python';
    }

    throw StateError("Could not determine agent type for '$agentName'.");
  }

  /// Returns `true` if [agent] configures a [ComputerUseToolset].
  bool isComputerUseAgent(BaseAgent agent) {
    bool hasComputerUse = false;
    final dynamic dynamicAgent = agent;
    if (dynamicAgent.tools is List<Object>) {
      for (final Object tool in (dynamicAgent.tools as List<Object>)) {
        if (tool is ComputerUseToolset) {
          hasComputerUse = true;
          break;
        }
        if (tool is BaseToolset) {
          // Keep a best-effort check without forcing async toolset expansion.
          continue;
        }
        if (tool is BaseTool || tool is FunctionTool) {
          continue;
        }
      }
    }
    return hasComputerUse;
  }

  /// Removes [agentName] from the in-memory loader cache.
  void removeAgentFromCache(String agentName) {
    _agentCache.remove(agentName);
  }

  _ResolvedAgentTarget _resolveAgentTarget(String agentName) {
    final String normalized = _normalizeAgentName(agentName);
    _validateAgentName(agentName, normalized);

    final Directory baseDir = Directory(agentsDir).absolute;
    if (_forcedSingleAgent == true) {
      return _ResolvedAgentTarget(
        normalizedName: normalized,
        agentDir: _agentDirectory(baseDir, normalized),
        agentParentForEnv: baseDir.path,
      );
    }
    if (_forcedSingleAgent == null && _isSingleAppRoot(baseDir)) {
      return _ResolvedAgentTarget(
        normalizedName: normalized,
        agentDir: baseDir,
        agentParentForEnv: baseDir.parent.path,
      );
    }

    return _ResolvedAgentTarget(
      normalizedName: normalized,
      agentDir: _agentDirectory(baseDir, normalized),
      agentParentForEnv: baseDir.path,
    );
  }

  void _validateAgentName(String agentName, String normalized) {
    if (normalized.contains('\n') ||
        normalized.contains('\r') ||
        !_validAgentNameRegExp.hasMatch(normalized)) {
      throw ArgumentError.value(
        agentName,
        'agentName',
        'Agent names must use letters, digits, and underscores only.',
      );
    }

    final Directory baseDir = Directory(agentsDir).absolute;
    if (_forcedSingleAgent == true) {
      if (normalized == _forcedSingleAgentName) {
        final Directory agentDir = _agentDirectory(baseDir, normalized);
        if (agentDir.existsSync()) {
          return;
        }
      }
      throw ArgumentError.value(
        agentName,
        'agentName',
        "Agent not found: '$agentName'. In single agent mode, only '$_forcedSingleAgentName' is accessible.",
      );
    }

    if (_forcedSingleAgent == null && _isSingleAppRoot(baseDir)) {
      if (_allowedSingleRootNames(baseDir).contains(normalized)) {
        return;
      }
      throw ArgumentError.value(
        agentName,
        'agentName',
        'Agent not found in single-app root ${baseDir.path}.',
      );
    }

    final Directory agentDir = _agentDirectory(baseDir, normalized);
    if (agentDir.existsSync()) {
      return;
    }
    throw ArgumentError.value(
      agentName,
      'agentName',
      'No matching directory exists in ${agentDir.path}.',
    );
  }

  String _normalizeAgentName(String agentName) {
    return agentName.startsWith('__') ? agentName.substring(2) : agentName;
  }

  Directory _agentDirectory(Directory baseDir, String normalized) {
    return Directory(
      '${baseDir.path}${Platform.pathSeparator}$normalized',
    ).absolute;
  }

  Set<String> _allowedSingleRootNames(Directory dir) {
    final Set<String> names = <String>{projectDirName(dir.path)};
    final String? alias = singleRootConfiguredAlias(dir);
    if (alias != null && alias.isNotEmpty) {
      names.add(alias);
    }
    return names;
  }

  /// Returns the `appName` configured in `adk.json` under [dir], if present.
  String? singleRootConfiguredAlias(Directory dir) {
    final File adkJson = File('${dir.path}${Platform.pathSeparator}adk.json');
    if (!adkJson.existsSync()) {
      return null;
    }
    try {
      return loadDevProjectConfigSync(dir.path).appName;
    } on Object {
      return null;
    }
  }

  String _singleRootAgentName(Directory dir) {
    return singleRootConfiguredAlias(dir) ?? projectDirName(dir.path);
  }
}

final class _ResolvedAgentTarget {
  const _ResolvedAgentTarget({
    required this.normalizedName,
    required this.agentDir,
    required this.agentParentForEnv,
  });

  final String normalizedName;
  final Directory agentDir;
  final String agentParentForEnv;
}

bool _isSingleAppRoot(Directory dir) => isSingleAgentDirectory(dir);

/// Loads a [DevProjectConfig] synchronously from [projectDirPath].
DevProjectConfig loadDevProjectConfigSync(String projectDirPath) {
  final Directory dir = Directory(projectDirPath);
  final File configFile = File('${dir.path}${Platform.pathSeparator}adk.json');
  final String fallbackName = projectDirName(projectDirPath);

  if (!configFile.existsSync()) {
    return DevProjectConfig(
      appName: fallbackName,
      agentName: 'root_agent',
      description: 'A development agent generated by adk_dart.',
    );
  }

  final Object? decoded = jsonDecode(configFile.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('adk.json must contain a JSON object.');
  }

  String readString(String key, String fallback) {
    final Object? value = decoded[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  return DevProjectConfig(
    appName: readString('appName', fallbackName),
    agentName: readString('agentName', 'root_agent'),
    description: readString(
      'description',
      'A development agent generated by adk_dart.',
    ),
    userId: readString('userId', 'user'),
  );
}

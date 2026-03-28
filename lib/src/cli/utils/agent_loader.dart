/// Filesystem-backed loader for CLI agent and app discovery.
library;

import 'dart:io';
import 'dart:convert';

import '../../agents/base_agent.dart';
import '../../agents/config_agent_utils.dart' as config_agent_utils;
import '../../tools/computer_use/computer_use_toolset.dart';
import '../../tools/function_tool.dart';
import '../../tools/base_toolset.dart';
import '../../tools/base_tool.dart';
import '../../dev/project.dart' show DevProjectConfig, projectDirName;
import '../../dev/runtime.dart';
import 'base_agent_loader.dart';
import 'envs.dart';

/// Factory signature used to resolve an agent at runtime.
typedef AgentFactory = AgentOrApp Function(String agentName, String agentsDir);

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
  final String agentsDir;
  final Map<String, AgentFactory> _agentFactories;
  final bool _enableDevProjectFallback;
  final Map<String, AgentOrApp> _agentCache = <String, AgentOrApp>{};

  /// Loads [agentName] and caches the result for subsequent lookups.
  @override
  AgentOrApp loadAgent(String agentName) {
    final AgentOrApp? cached = _agentCache[agentName];
    if (cached != null) {
      return cached;
    }

    final AgentOrApp loaded = _performLoad(agentName);
    _agentCache[agentName] = loaded;
    return loaded;
  }

  AgentOrApp _performLoad(String agentName) {
    final AgentFactory? customFactory = _agentFactories[agentName];
    if (customFactory != null) {
      return customFactory(agentName, agentsDir);
    }

    final _ResolvedAgentTarget target = _resolveAgentTarget(agentName);

    loadDotenvForAgent(target.normalizedName, target.agentParentForEnv);

    final File rootAgentYaml = File(
      '${target.agentDir.path}${Platform.pathSeparator}root_agent.yaml',
    );
    if (rootAgentYaml.existsSync()) {
      return config_agent_utils.fromConfig(rootAgentYaml.path);
    }

    final File adkJson = File(
      '${target.agentDir.path}${Platform.pathSeparator}adk.json',
    );
    final File agentDart = File(
      '${target.agentDir.path}${Platform.pathSeparator}agent.dart',
    );
    if (_enableDevProjectFallback &&
        (adkJson.existsSync() || agentDart.existsSync())) {
      final DevProjectConfig config = _loadDevProjectConfigSync(
        target.agentDir.path,
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      return runtime.runner.agent;
    }

    throw StateError(
      "No root agent found for '$agentName'. Expected either "
      "'${target.normalizedName}/root_agent.yaml' or "
      "'${target.normalizedName}/agent.dart' under $agentsDir.",
    );
  }

  /// All visible agent directory names under [agentsDir].
  @override
  List<String> listAgents() {
    final Directory base = Directory(agentsDir).absolute;
    if (!base.existsSync()) {
      return <String>[];
    }

    if (_isSingleAppRoot(base)) {
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
        final String language = _determineAgentLanguage(agentName);
        final bool isComputerUse = _isComputerUseAgent(root);
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

  String _determineAgentLanguage(String agentName) {
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

    throw StateError("Could not determine agent type for '$agentName'.");
  }

  bool _isComputerUseAgent(BaseAgent agent) {
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
    if (_isSingleAppRoot(baseDir)) {
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
    if (!_validAgentNameRegExp.hasMatch(normalized)) {
      throw ArgumentError.value(
        agentName,
        'agentName',
        'Agent names must use letters, digits, and underscores only.',
      );
    }

    final Directory baseDir = Directory(agentsDir).absolute;
    if (_isSingleAppRoot(baseDir)) {
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
    final String? alias = _singleRootConfiguredAlias(dir);
    if (alias != null && alias.isNotEmpty) {
      names.add(alias);
    }
    return names;
  }

  String? _singleRootConfiguredAlias(Directory dir) {
    final File adkJson = File('${dir.path}${Platform.pathSeparator}adk.json');
    if (!adkJson.existsSync()) {
      return null;
    }
    try {
      return _loadDevProjectConfigSync(dir.path).appName;
    } on Object {
      return null;
    }
  }

  String _singleRootAgentName(Directory dir) {
    return _singleRootConfiguredAlias(dir) ?? projectDirName(dir.path);
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

bool _isSingleAppRoot(Directory dir) {
  final String path = dir.path;
  final String sep = Platform.pathSeparator;
  return File('$path${sep}adk.json').existsSync() ||
      File('$path${sep}agent.dart').existsSync() ||
      File('$path${sep}root_agent.yaml').existsSync();
}

DevProjectConfig _loadDevProjectConfigSync(String projectDirPath) {
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

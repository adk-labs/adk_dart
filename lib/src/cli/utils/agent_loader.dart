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

typedef AgentFactory = AgentOrApp Function(String agentName, String agentsDir);

class AgentLoader extends BaseAgentLoader {
  AgentLoader(this.agentsDir, {Map<String, AgentFactory>? agentFactories})
    : _agentFactories = agentFactories ?? <String, AgentFactory>{};

  final String agentsDir;
  final Map<String, AgentFactory> _agentFactories;
  final Map<String, AgentOrApp> _agentCache = <String, AgentOrApp>{};

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
    final String normalized = agentName.startsWith('__')
        ? agentName.substring(2)
        : agentName;

    final AgentFactory? customFactory = _agentFactories[agentName];
    if (customFactory != null) {
      return customFactory(agentName, agentsDir);
    }

    final Directory baseDir = Directory(agentsDir).absolute;
    final Directory agentDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}$normalized',
    ).absolute;

    loadDotenvForAgent(normalized, baseDir.path);

    final File rootAgentYaml = File(
      '${agentDir.path}${Platform.pathSeparator}root_agent.yaml',
    );
    if (rootAgentYaml.existsSync()) {
      return config_agent_utils.fromConfig(rootAgentYaml.path);
    }

    final File adkJson = File(
      '${agentDir.path}${Platform.pathSeparator}adk.json',
    );
    final File agentDart = File(
      '${agentDir.path}${Platform.pathSeparator}agent.dart',
    );
    if (adkJson.existsSync() || agentDart.existsSync()) {
      final DevProjectConfig config = _loadDevProjectConfigSync(agentDir.path);
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      return runtime.runner.agent;
    }

    throw StateError(
      "No root agent found for '$agentName'. Expected either "
      "'$normalized/root_agent.yaml' or '$normalized/agent.dart' under $agentsDir.",
    );
  }

  @override
  List<String> listAgents() {
    final Directory base = Directory(agentsDir).absolute;
    if (!base.existsSync()) {
      return <String>[];
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
    final Directory basePath = Directory(
      '${Directory(agentsDir).absolute.path}${Platform.pathSeparator}$agentName',
    );

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

  void removeAgentFromCache(String agentName) {
    _agentCache.remove(agentName);
  }
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

/// File-change handlers used by reload-capable CLI workflows.
library;

import 'dart:io';

import 'agent_loader.dart';
import 'base_agent_loader.dart';
import 'shared_value.dart';

/// Handles agent source file change events for cache invalidation.
class AgentChangeEventHandler {
  /// Creates a file-change event handler for the active app or [agentsDir].
  AgentChangeEventHandler({
    required this.agentLoader,
    required this.runnersToClean,
    this.currentAppNameRef,
    Object? agentsDir,
  }) : agentsDir = agentsDir == null
           ? null
           : (agentsDir is Directory
                 ? agentsDir.absolute.path
                 : Directory('$agentsDir').absolute.path);

  /// Agent loader cache manager.
  final BaseAgentLoader agentLoader;

  /// App names whose runners should be restarted.
  final Set<String> runnersToClean;

  /// Optional mutable pointer to the currently selected app name.
  final SharedValue<String>? currentAppNameRef;

  /// Optional resolved root directory containing watched agents.
  final String? agentsDir;

  /// Processes one modified [sourcePath] and marks affected apps for reload.
  void onModified(String sourcePath) {
    final String lower = sourcePath.toLowerCase();
    if (!lower.endsWith('.py') &&
        !lower.endsWith('.yaml') &&
        !lower.endsWith('.yml') &&
        !lower.endsWith('.dart')) {
      return;
    }

    if (agentsDir == null) {
      final SharedValue<String>? ref = currentAppNameRef;
      if (ref != null) {
        _removeAgentFromCache(ref.value);
        runnersToClean.add(ref.value);
      }
      return;
    }

    final Directory rootDir = Directory(agentsDir!).absolute;
    final File filePath = File(sourcePath).absolute;
    final String? relPath = _relativeTo(rootDir.path, filePath.path);
    if (relPath == null || relPath.isEmpty) {
      return;
    }

    final List<String> relParts = relPath
        .split('/')
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (relParts.isEmpty) {
      return;
    }

    final List<String> agentNames = <String>[];
    if (relParts.length == 1) {
      final String fileName = relParts.first;
      final int dotIndex = fileName.lastIndexOf('.');
      final String stem = dotIndex > 0
          ? fileName.substring(0, dotIndex)
          : fileName;
      agentNames.add(stem);
    } else {
      Directory curr = filePath.parent.absolute;
      while (curr.path != rootDir.path && curr.parent.path != curr.path) {
        if (isSingleAgentDirectory(curr)) {
          final String? currRel = _relativeTo(rootDir.path, curr.path);
          if (currRel != null && currRel.isNotEmpty) {
            agentNames.add(
              currRel
                  .split('/')
                  .where((String part) => part.isNotEmpty)
                  .join('.'),
            );
          }
        }
        curr = curr.parent.absolute;
      }

      final String topLevelName = relParts.first;
      final Directory topLevelDir = Directory(
        '${rootDir.path}${Platform.pathSeparator}$topLevelName',
      );
      final bool hasInitPy = File(
        '${topLevelDir.path}${Platform.pathSeparator}__init__.py',
      ).existsSync();
      if (hasInitPy || agentNames.isNotEmpty) {
        if (!agentNames.contains(topLevelName)) {
          agentNames.add(topLevelName);
        }
      }
    }

    for (final String agentName in agentNames) {
      _removeAgentFromCache(agentName);
      runnersToClean.add(agentName);
    }
  }

  void _removeAgentFromCache(String agentName) {
    final BaseAgentLoader loader = agentLoader;
    if (loader is AgentLoader) {
      loader.removeAgentFromCache(agentName);
    }
  }
}

String? _relativeTo(String baseDirPath, String targetPath) {
  String normBase = Directory(baseDirPath).absolute.path.replaceAll('\\', '/');
  final String normTarget = File(
    targetPath,
  ).absolute.path.replaceAll('\\', '/');
  if (!normBase.endsWith('/')) {
    normBase = '$normBase/';
  }
  if (!normTarget.startsWith(normBase)) {
    return null;
  }
  return normTarget.substring(normBase.length);
}

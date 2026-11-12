/// Base contracts and conversion helpers for CLI agent loaders.
library;

import 'dart:io';

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/apps/app.dart';
import 'package:adk_dart/src/workflow/workflow.dart';

/// Union type used by loaders that can return an [App], [BaseAgent], or
/// workflow [BaseNode].
typedef AgentOrApp = Object;

/// Alias matching the Python type alias `NodeOrApp` (`BaseNode | BaseAgent | App`).
typedef NodeOrApp = AgentOrApp;

final Expando<String> _originAppNameExpando = Expando<String>(
  '_adk_origin_app_name',
);
final Expando<Directory> _originPathExpando = Expando<Directory>(
  '_adk_origin_path',
);

/// Error thrown when an agent exists on disk but fails while loading.
///
/// Deliberately distinct from [ArgumentError], which indicates no such agent.
class AgentLoadError extends StateError {
  /// Creates an agent load error with [message].
  AgentLoadError(super.message);
}

/// Returns the recorded `_adk_origin_app_name` metadata for [target], if any.
String? getAgentOriginAppName(Object? target) {
  if (target == null) {
    return null;
  }
  return _originAppNameExpando[target];
}

/// Returns the recorded `_adk_origin_path` metadata for [target], if any.
Directory? getAgentOriginPath(Object? target) {
  if (target == null) {
    return null;
  }
  return _originPathExpando[target];
}

/// Attaches origin metadata (`_adk_origin_app_name` and `_adk_origin_path`)
/// to [loaded] (and `loaded.rootAgent` when [loaded] is an [App]).
void attachAgentOriginMetadata({
  required AgentOrApp loaded,
  required String expectedAppName,
  required Directory originPath,
}) {
  if (expectedAppName.startsWith('__')) {
    return;
  }
  _originAppNameExpando[loaded] = expectedAppName;
  _originPathExpando[loaded] = originPath;
  if (loaded is App) {
    _originAppNameExpando[loaded.rootAgent] = expectedAppName;
    _originPathExpando[loaded.rootAgent] = originPath;
  }
}

/// Loads root agents and app metadata from an agents directory.
abstract class BaseAgentLoader {
  /// Whether special internal agents (`__...`) may be loaded.
  bool allowSpecialAgents = false;

  /// Loads a single agent or app identified by [agentName].
  AgentOrApp loadAgent(String agentName);

  /// All available agent names under this loader's root.
  List<String> listAgents();

  /// Rich agent metadata for UI listing endpoints.
  ///
  /// Subclasses can override this to include extra fields.
  List<Map<String, Object?>> listAgentsDetailed() {
    return listAgents()
        .map(
          (String name) => <String, Object?>{
            'name': name,
            'display_name': null,
            'description': null,
            'type': null,
          },
        )
        .toList(growable: false);
  }
}

/// Returns `true` when [value] is a standalone workflow [BaseNode] that is not
/// already a [BaseAgent] (for example, `Node` or `FunctionNode`).
bool isStandaloneWorkflowNode(Object? value) {
  return value is BaseNode && value is! BaseAgent;
}

/// Extracts the root [BaseAgent] or workflow [BaseNode] from [value].
///
/// Returns `value.rootAgent` when [value] is an [App], or [value] directly
/// when it is a [BaseAgent] or [BaseNode].
///
/// Throws an [ArgumentError] when [value] is none of [App], [BaseAgent], or
/// [BaseNode].
Object asRootNodeOrAgent(AgentOrApp value) {
  if (value is App) {
    return value.rootAgent;
  }
  if (value is BaseAgent || value is BaseNode) {
    return value;
  }
  throw ArgumentError(
    'Loaded object is neither App, BaseAgent, nor BaseNode.',
  );
}

/// Converts [value] to an executable [BaseAgent].
///
/// Returns `value.rootAgent` when [value] is an [App], [value] directly when
/// it is a [BaseAgent], or wraps a standalone workflow [BaseNode] in a
/// single-node [Workflow].
///
/// Throws an [ArgumentError] when [value] is none of [App], [BaseAgent], or
/// [BaseNode].
BaseAgent asBaseAgent(AgentOrApp value) {
  if (value is App) {
    return value.rootAgent;
  }
  if (value is BaseAgent) {
    return value;
  }
  if (value is BaseNode) {
    return Workflow(
      name: value.name,
      description: value.description,
      nodes: <BaseNode>[value],
      edges: <Edge>[Edge(fromNode: START, toNode: value)],
    );
  }
  throw ArgumentError(
    'Loaded object is neither App, BaseAgent, nor BaseNode.',
  );
}

/// Base contracts and conversion helpers for CLI agent loaders.
library;

import 'dart:io';

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/apps/app.dart';

/// Union type used by loaders that can return either an [App] or [BaseAgent].
typedef AgentOrApp = Object;

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

/// Converts [value] to a [BaseAgent].
///
/// Returns `value.rootAgent` when [value] is an [App].
///
/// Throws an [ArgumentError] when [value] is neither [App] nor [BaseAgent].
BaseAgent asBaseAgent(AgentOrApp value) {
  if (value is App) {
    return value.rootAgent;
  }
  if (value is BaseAgent) {
    return value;
  }
  throw ArgumentError('Loaded object is neither App nor BaseAgent.');
}

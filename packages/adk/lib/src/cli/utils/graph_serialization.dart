/// JSON-safe graph serialization utilities for ADK web/CLI surfaces.
library;

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/apps/app.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/plugins/base_plugin.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/base_toolset.dart';
import 'package:adk_dart/src/workflow/workflow.dart';

/// JSON-compatible object map.
typedef GraphJson = Map<String, Object?>;

/// Serializes an app for graph-oriented web UI endpoints.
GraphJson serializeAppInfo(App app, {String? readme}) {
  final GraphJson result = <String, Object?>{
    'name': app.name,
    'root_agent': serializeAgent(app.rootAgent),
  };
  if (app.plugins.isNotEmpty) {
    result['plugins'] = app.plugins
        .map((BasePlugin plugin) => <String, Object?>{'name': plugin.name})
        .toList();
  }
  if (app.contextCacheConfig != null) {
    result['context_cache_config'] = _jsonSafeValue(app.contextCacheConfig);
  }
  if (app.resumabilityConfig != null) {
    result['resumability_config'] = _jsonSafeValue(app.resumabilityConfig);
  }
  if (readme != null) {
    result['readme'] = readme;
  }
  return result;
}

/// Recursively serializes [agent] into JSON-safe fields.
GraphJson serializeAgent(BaseAgent agent) {
  final GraphJson result = <String, Object?>{
    'name': agent.name,
    'type': _agentType(agent),
  };
  if (agent.description.isNotEmpty) {
    result['description'] = agent.description;
  }

  if (agent is LlmAgent) {
    result.addAll(_serializeLlmAgentFields(agent));
  }
  if (agent is Workflow) {
    final List<GraphJson> nodes = agent.nodes.map(serializeNode).toList();
    final List<GraphJson> edges = agent.edges.map(serializeEdge).toList();
    result['nodes'] = nodes;
    result['edges'] = edges;
    result['graph'] = <String, Object?>{'nodes': nodes, 'edges': edges};
  } else if (agent.subAgents.isNotEmpty) {
    result['sub_agents'] = agent.subAgents.map(serializeAgent).toList();
  }

  return result;
}

/// Serializes a workflow node.
GraphJson serializeNode(BaseNode node) {
  final GraphJson result = <String, Object?>{
    'name': node.name,
    'type': _nodeType(node),
    'rerun_on_resume': node.rerunOnResume,
    'wait_for_output': node.waitForOutput,
  };
  if (node.description.isNotEmpty) {
    result['description'] = node.description;
  }
  if (node.dependsOn.isNotEmpty) {
    result['depends_on'] = node.dependsOn;
  }
  if (node is AgentNode) {
    result['agent'] = serializeAgent(node.agent);
  } else if (node is ToolNode) {
    result['tool'] = _serializeToolLike(node.tool);
  }
  return result;
}

/// Serializes one workflow edge.
GraphJson serializeEdge(Edge edge) {
  return <String, Object?>{
    'from_node': edge.fromNode,
    'to_node': edge.toNode,
    if (edge.route != null) 'route': _jsonSafeValue(edge.route),
  };
}

GraphJson _serializeLlmAgentFields(LlmAgent agent) {
  final GraphJson result = <String, Object?>{
    'model': _serializeModel(agent.model),
  };
  if (agent.instruction is String && (agent.instruction as String).isNotEmpty) {
    result['instruction'] = agent.instruction;
  }
  if (agent.globalInstruction is String &&
      (agent.globalInstruction as String).isNotEmpty) {
    result['global_instruction'] = agent.globalInstruction;
  }
  if (agent.staticInstruction != null) {
    result['static_instruction'] = _jsonSafeValue(agent.staticInstruction);
  }
  if (agent.tools.isNotEmpty) {
    result['tools'] = agent.tools.map(_serializeToolLike).toList();
  }
  if (agent.subAgents.isNotEmpty) {
    result['sub_agents'] = agent.subAgents.map(serializeAgent).toList();
  }
  if (agent.mode != null) {
    result['mode'] = agent.mode;
  }
  if (agent.includeContents != 'default') {
    result['include_contents'] = agent.includeContents;
  }
  if (agent.outputKey != null) {
    result['output_key'] = agent.outputKey;
  }
  return result;
}

Object? _serializeModel(Object model) {
  if (model is BaseLlm) {
    return model.model;
  }
  return _jsonSafeValue(model);
}

Object? _serializeToolLike(Object tool) {
  if (tool is BaseTool) {
    return <String, Object?>{
      'name': tool.name,
      'type': 'tool',
      if (tool.description.isNotEmpty) 'description': tool.description,
    };
  }
  if (tool is BaseToolset) {
    return <String, Object?>{
      'name': tool.runtimeType.toString(),
      'type': 'tool',
    };
  }
  if (tool is BaseAgent) {
    return serializeAgent(tool);
  }
  return <String, Object?>{'name': _callableName(tool), 'type': 'tool'};
}

String _agentType(BaseAgent agent) {
  if (agent is Workflow) {
    return 'workflow';
  }
  if (agent is LlmAgent) {
    return 'agent';
  }
  return 'agent';
}

String _nodeType(BaseNode node) {
  if (node is FunctionNode) {
    return 'function';
  }
  if (node is ToolNode) {
    return 'tool';
  }
  if (node is AgentNode) {
    return 'agent';
  }
  if (node is JoinNode) {
    return 'join';
  }
  return 'node';
}

String _callableName(Object value) {
  final String raw = value.toString();
  final int closureIndex = raw.indexOf('Closure: ');
  if (closureIndex >= 0) {
    return raw.substring(closureIndex + 'Closure: '.length);
  }
  return raw;
}

Object? _jsonSafeValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is BaseLlm) {
    return value.model;
  }
  if (value is Iterable) {
    return value.map(_jsonSafeValue).toList();
  }
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<dynamic, dynamic> entry in value.entries)
        '${entry.key}': _jsonSafeValue(entry.value),
    };
  }
  try {
    final Object? json = (value as dynamic).toJson();
    if (json != value) {
      return _jsonSafeValue(json);
    }
  } catch (_) {
    // Fall through to stringification for non-serializable runtime objects.
  }
  return value.toString();
}

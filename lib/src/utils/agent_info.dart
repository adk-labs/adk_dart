/// Utilities for inspecting [LlmAgent] hierarchies and tool declarations.
library;

import 'dart:developer' as developer;

import '../agents/base_agent.dart';
import '../agents/llm_agent.dart';
import '../models/llm_request.dart';
import '../tools/base_tool.dart';
import '../tools/base_toolset.dart';
import '../tools/function_tool.dart';
import '../tools/node_tool.dart';
import '../workflow/workflow.dart';

/// Metadata summary for an [LlmAgent] and its sub-agents.
///
/// ```dart
/// final info = await getAgentsDict(rootAgent);
/// print(info[rootAgent.name]?.subAgents);
/// ```
class AgentInfo {
  /// Creates an [AgentInfo] summary.
  AgentInfo({
    required this.name,
    required this.description,
    required Object instruction,
    List<ToolDeclaration>? tools,
    List<String>? subAgents,
  }) : instruction = _coerceInstruction(instruction),
       tools = List<ToolDeclaration>.unmodifiable(
         tools ?? const <ToolDeclaration>[],
       ),
       subAgents = List<String>.unmodifiable(subAgents ?? const <String>[]);

  /// Agent name.
  final String name;

  /// Agent description.
  final String description;

  /// Static instruction string or `<InstructionProvider: ...>` placeholder.
  final String instruction;

  /// Resolved tool declarations exposed by the agent.
  final List<ToolDeclaration> tools;

  /// Names of child [LlmAgent] sub-agents.
  final List<String> subAgents;

  static String _coerceInstruction(Object value) {
    if (value is String) {
      return value;
    }
    if (value is Function) {
      return '<InstructionProvider: ${value.runtimeType}>';
    }
    return '$value';
  }

  /// Serializes this [AgentInfo] to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'instruction': instruction,
      'tools': tools
          .map(
            (ToolDeclaration t) => <String, Object?>{
              'function_declarations': t.functionDeclarations
                  .map(
                    (FunctionDeclaration d) => <String, Object?>{
                      'name': d.name,
                      'description': d.description,
                      'parameters': d.parameters,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
      'sub_agents': subAgents,
    };
  }
}

/// Resolves [ToolDeclaration] items for a list of agent [tools].
Future<List<ToolDeclaration>> getToolsInfo(List<Object> tools) async {
  final List<BaseTool> finalTools = <BaseTool>[];
  for (final Object tool in tools) {
    if (tool is BaseTool) {
      finalTools.add(tool);
    } else if (tool is BaseNode) {
      finalTools.add(NodeTool(node: tool));
    } else if (tool is BaseToolset) {
      final List<BaseTool> resolved = await tool.getTools();
      finalTools.addAll(resolved);
    } else if (tool is Function) {
      finalTools.add(FunctionTool(func: tool));
    }
  }

  final List<ToolDeclaration> declarations = <ToolDeclaration>[];
  for (final BaseTool tool in finalTools) {
    final FunctionDeclaration? decl = tool.getDeclaration();
    if (decl != null) {
      declarations.add(
        ToolDeclaration(functionDeclarations: <FunctionDeclaration>[decl]),
      );
    }
  }
  return declarations;
}

Iterable<Object> _iterStaticChildren(Object node) {
  if (node is Workflow) {
    return <Object>[...node.subAgents, ...node.nodes];
  }
  if (node is LlmAgent) {
    return <Object>[
      ...node.subAgents,
      for (final Object tool in node.tools)
        if (tool is NodeTool)
          tool.node
        else if (tool is BaseNode)
          tool,
    ];
  }
  if (node is BaseAgent) {
    return node.subAgents;
  }
  if (node is AgentNode) {
    return <Object>[node.agent];
  }
  if (node is ParallelWorker) {
    return <Object>[node.wrappedNode];
  }
  return const <Object>[];
}

Iterable<Object> _walkStaticNodes(Object root) sync* {
  final Set<Object> visited = Set<Object>.identity();
  final List<Object> stack = <Object>[root];
  while (stack.isNotEmpty) {
    final Object current = stack.removeLast();
    if (!visited.add(current)) {
      continue;
    }
    yield current;
    final List<Object> children = _iterStaticChildren(current).toList();
    for (int i = children.length - 1; i >= 0; i -= 1) {
      stack.add(children[i]);
    }
  }
}

List<String> _nearestLlmSubAgentNames(BaseAgent agent) {
  final Set<String> names = <String>{};
  final Set<BaseAgent> visited = Set<BaseAgent>.identity()..add(agent);

  void collect(BaseAgent current) {
    for (final BaseAgent subAgent in current.subAgents) {
      if (!visited.add(subAgent)) {
        continue;
      }
      if (subAgent is LlmAgent) {
        names.add(subAgent.name);
      } else {
        collect(subAgent);
      }
    }
  }

  collect(agent);
  return names.toList(growable: false);
}

/// Returns a map of [AgentInfo] keyed by agent name for every [LlmAgent]
/// reachable from [agent] (which may be an [LlmAgent], any non-LLM
/// [BaseAgent] such as `SequentialAgent` or [Workflow], or a [BaseNode]).
Future<Map<String, AgentInfo>> getAgentsDict(Object agent) async {
  final Map<String, AgentInfo> agentsDict = <String, AgentInfo>{};

  for (final Object node in _walkStaticNodes(agent)) {
    if (node is! LlmAgent) {
      continue;
    }
    if (agentsDict.containsKey(node.name)) {
      developer.log(
        "Duplicate LlmAgent name '${node.name}' encountered while collecting "
        'app info; keeping first agent.',
        name: 'adk_dart.agent_info',
      );
      continue;
    }

    agentsDict[node.name] = AgentInfo(
      name: node.name,
      description: node.description,
      instruction: node.instruction,
      tools: await getToolsInfo(node.tools),
      subAgents: _nearestLlmSubAgentNames(node),
    );
  }

  return agentsDict;
}

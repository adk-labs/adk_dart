/// Utilities for inspecting [LlmAgent] hierarchies and tool declarations.
library;

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

/// Returns a map of [AgentInfo] keyed by agent name for [agent] and its
/// [LlmAgent] sub-agents.
Future<Map<String, AgentInfo>> getAgentsDict(LlmAgent agent) async {
  final Map<String, AgentInfo> agentsDict = <String, AgentInfo>{};

  Future<void> traverse(LlmAgent currentAgent) async {
    if (agentsDict.containsKey(currentAgent.name)) {
      return;
    }

    final List<String> subAgentNames = <String>[];
    for (final BaseAgent subAgent in currentAgent.subAgents) {
      if (subAgent is LlmAgent) {
        await traverse(subAgent);
        subAgentNames.add(subAgent.name);
      }
    }

    agentsDict[currentAgent.name] = AgentInfo(
      name: currentAgent.name,
      description: currentAgent.description,
      instruction: currentAgent.instruction,
      tools: await getToolsInfo(currentAgent.tools),
      subAgents: subAgentNames,
    );
  }

  await traverse(agent);
  return agentsDict;
}

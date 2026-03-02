/// Agent graph builders used by CLI visualization endpoints.
library;

import '../agents/base_agent.dart';
import '../agents/llm_agent.dart';
import '../tools/base_tool.dart';
import '../tools/function_tool.dart';

/// Node model used by CLI graph output.
class AgentGraphNode {
  /// Creates one graph node with [id], [caption], and [kind].
  AgentGraphNode({required this.id, required this.caption, required this.kind});

  /// Stable node identifier.
  final String id;

  /// Human-readable node label.
  final String caption;

  /// Node category, for example `agent` or `tool`.
  final String kind;
}

/// Graph model containing agent and tool relationships.
class AgentGraph {
  /// Creates a graph with [nodes] and directed [edges].
  AgentGraph({required this.nodes, required this.edges});

  /// All nodes in the graph.
  final List<AgentGraphNode> nodes;

  /// Directed edges represented as `(from, to)` pairs.
  final List<(String, String)> edges;
}

/// Builds an [AgentGraph] from [rootAgent] and its reachable children/tools.
Future<AgentGraph> buildGraph(BaseAgent rootAgent) async {
  final Map<String, AgentGraphNode> nodes = <String, AgentGraphNode>{};
  final Set<(String, String)> edges = <(String, String)>{};

  Future<void> visitAgent(BaseAgent agent) async {
    nodes.putIfAbsent(
      agent.name,
      () => AgentGraphNode(
        id: agent.name,
        caption: '🤖 ${agent.name}',
        kind: 'agent',
      ),
    );

    for (final BaseAgent subAgent in agent.subAgents) {
      await visitAgent(subAgent);
      edges.add((agent.name, subAgent.name));
    }

    if (agent is LlmAgent) {
      final List<BaseTool> tools = await agent.canonicalTools();
      for (final BaseTool tool in tools) {
        final String toolNodeId = 'tool:${tool.name}';
        final String caption = tool is FunctionTool
            ? '🔧 ${tool.name}'
            : '🧰 ${tool.name}';
        nodes.putIfAbsent(
          toolNodeId,
          () => AgentGraphNode(id: toolNodeId, caption: caption, kind: 'tool'),
        );
        edges.add((agent.name, toolNodeId));
      }
    }
  }

  await visitAgent(rootAgent);
  return AgentGraph(
    nodes: nodes.values.toList(growable: false),
    edges: edges.toList(growable: false),
  );
}

/// Returns Mermaid flowchart text for the graph rooted at [rootAgent].
///
/// Edges in [highlightPairs] are rendered with emphasized connectors.
Future<String> getAgentGraph(
  BaseAgent rootAgent, {
  Set<(String, String)> highlightPairs = const <(String, String)>{},
}) async {
  final AgentGraph graph = await buildGraph(rootAgent);
  final StringBuffer out = StringBuffer('flowchart LR\n');

  for (final AgentGraphNode node in graph.nodes) {
    final String safeId = _toMermaidId(node.id);
    out.writeln('  $safeId["${node.caption}"]');
  }

  for (final (String from, String to) in graph.edges) {
    final bool highlighted =
        highlightPairs.contains((from, to)) ||
        highlightPairs.contains((to, from));
    final String fromId = _toMermaidId(from);
    final String toId = _toMermaidId(to);
    if (highlighted) {
      out.writeln('  $fromId ==>$toId');
    } else {
      out.writeln('  $fromId --> $toId');
    }
  }

  return out.toString().trimRight();
}

String _toMermaidId(String raw) {
  return raw.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
}

import '../agents/base_agent.dart';
import '../agents/llm_agent.dart';
import '../tools/base_tool.dart';
import '../tools/function_tool.dart';

class AgentGraphNode {
  AgentGraphNode({required this.id, required this.caption, required this.kind});

  final String id;
  final String caption;
  final String kind;
}

class AgentGraph {
  AgentGraph({required this.nodes, required this.edges});

  final List<AgentGraphNode> nodes;
  final List<(String, String)> edges;
}

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

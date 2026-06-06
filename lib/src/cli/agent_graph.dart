/// Agent graph builders used by CLI visualization endpoints.
library;

import '../agents/base_agent.dart';
import '../agents/llm_agent.dart';
import '../tools/base_tool.dart';
import '../tools/function_tool.dart';
import '../workflow/workflow.dart';

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

/// Graph model containing agent, workflow node, and tool relationships.
class AgentGraph {
  /// Creates a graph with [nodes] and directed [edges].
  AgentGraph({
    required this.nodes,
    required this.edges,
    Map<(String, String), String>? edgeLabels,
  }) : edgeLabels = edgeLabels ?? const <(String, String), String>{};

  /// All nodes in the graph.
  final List<AgentGraphNode> nodes;

  /// Directed edges represented as `(from, to)` pairs.
  final List<(String, String)> edges;

  /// Optional labels keyed by directed edge pair.
  final Map<(String, String), String> edgeLabels;
}

/// Builds an [AgentGraph] from [rootAgent] and its reachable children/tools.
Future<AgentGraph> buildGraph(BaseAgent rootAgent) async {
  final Map<String, AgentGraphNode> nodes = <String, AgentGraphNode>{};
  final Set<(String, String)> edges = <(String, String)>{};
  final Map<(String, String), String> edgeLabels = <(String, String), String>{};

  void addEdge(String from, String to, {Object? label}) {
    final (String, String) edge = (from, to);
    edges.add(edge);
    if (label != null) {
      edgeLabels[edge] = '$label';
    }
  }

  late Future<void> Function(BaseAgent agent) visitAgent;
  late Future<void> Function(Workflow workflow) visitWorkflow;

  visitAgent = (BaseAgent agent) async {
    if (agent is Workflow) {
      await visitWorkflow(agent);
      return;
    }

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
      addEdge(agent.name, subAgent.name);
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
        addEdge(agent.name, toolNodeId);
      }
    }
  };

  visitWorkflow = (Workflow workflow) async {
    nodes.putIfAbsent(
      workflow.name,
      () => AgentGraphNode(
        id: workflow.name,
        caption: '🤖 ${workflow.name}',
        kind: 'workflow',
      ),
    );

    final Set<String> workflowNodeNames = <String>{
      for (final BaseNode node in workflow.nodes) node.name,
    };
    final Set<String> targetedNodes = <String>{};

    for (final BaseNode node in workflow.nodes) {
      final String nodeId = _workflowNodeId(workflow, node.name);
      nodes.putIfAbsent(
        nodeId,
        () => AgentGraphNode(
          id: nodeId,
          caption: _workflowNodeCaption(node),
          kind: _workflowNodeKind(node),
        ),
      );

      if (node is AgentNode) {
        await visitAgent(node.agent);
        addEdge(nodeId, node.agent.name);
      } else if (node is ToolNode) {
        final String toolNodeId = 'tool:${node.tool.name}';
        final String caption = node.tool is FunctionTool
            ? '🔧 ${node.tool.name}'
            : '🧰 ${node.tool.name}';
        nodes.putIfAbsent(
          toolNodeId,
          () => AgentGraphNode(id: toolNodeId, caption: caption, kind: 'tool'),
        );
        addEdge(nodeId, toolNodeId);
      }
    }

    for (final Edge edge in workflow.edges) {
      if (!workflowNodeNames.contains(edge.toNode)) {
        continue;
      }
      targetedNodes.add(edge.toNode);
      final String to = _workflowNodeId(workflow, edge.toNode);
      if (edge.fromNode == START) {
        addEdge(workflow.name, to, label: edge.route);
        continue;
      }
      if (!workflowNodeNames.contains(edge.fromNode)) {
        continue;
      }
      final String from = _workflowNodeId(workflow, edge.fromNode);
      addEdge(from, to, label: edge.route);
    }

    for (final BaseNode node in workflow.nodes) {
      final String to = _workflowNodeId(workflow, node.name);
      for (final String dependency in node.dependsOn) {
        if (workflowNodeNames.contains(dependency)) {
          targetedNodes.add(node.name);
          addEdge(_workflowNodeId(workflow, dependency), to);
        }
      }
    }

    for (final BaseNode node in workflow.nodes) {
      if (!targetedNodes.contains(node.name)) {
        addEdge(workflow.name, _workflowNodeId(workflow, node.name));
      }
    }
  };

  await visitAgent(rootAgent);
  return AgentGraph(
    nodes: nodes.values.toList(growable: false),
    edges: edges.toList(growable: false),
    edgeLabels: Map<(String, String), String>.unmodifiable(edgeLabels),
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
    final String? label = graph.edgeLabels[(from, to)];
    if (highlighted) {
      if (label == null) {
        out.writeln('  $fromId ==> $toId');
      } else {
        out.writeln('  $fromId == "${_escapeMermaidLabel(label)}" ==> $toId');
      }
    } else if (label == null) {
      out.writeln('  $fromId --> $toId');
    } else {
      out.writeln('  $fromId -- "${_escapeMermaidLabel(label)}" --> $toId');
    }
  }

  return out.toString().trimRight();
}

String _workflowNodeCaption(BaseNode node) {
  if (node is FunctionNode) {
    return '🔧 ${node.name}';
  }
  if (node is ToolNode) {
    return '🧰 ${node.name}';
  }
  if (node is AgentNode) {
    return '🤖 ${node.name}';
  }
  if (node is JoinNode) {
    return '🔀 ${node.name}';
  }
  return '◇ ${node.name}';
}

String _workflowNodeId(Workflow workflow, String nodeName) {
  return '${workflow.name}:$nodeName';
}

String _workflowNodeKind(BaseNode node) {
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
  return 'workflow_node';
}

String _toMermaidId(String raw) {
  return raw.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
}

String _escapeMermaidLabel(String value) {
  return value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
}

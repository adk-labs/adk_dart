/// Agent graph builders used by CLI visualization endpoints.
library;

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/function_tool.dart';
import 'package:adk_dart/src/workflow/workflow.dart';

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

/// Returns Graphviz DOT text for the graph rooted at [rootAgent].
///
/// This mirrors the Python web UI graph renderer closely enough for server
/// endpoints to expose status-aware workflow nodes, conditional branch
/// styling, tool edges, and terminal workflow nodes without requiring Graphviz
/// at runtime.
Future<String> getAgentGraphDot(
  BaseAgent rootAgent, {
  Set<(String, String)> highlightPairs = const <(String, String)>{},
  Map<String, NodeStatus> nodeStatuses = const <String, NodeStatus>{},
  bool darkMode = true,
}) async {
  final AgentGraph graph = await buildGraph(rootAgent);
  final Map<String, String> kindById = <String, String>{
    for (final AgentGraphNode node in graph.nodes) node.id: node.kind,
  };
  final _GraphDotTheme theme = _GraphDotTheme.fromDarkMode(darkMode);
  final StringBuffer out = StringBuffer('digraph G {\n');
  out.writeln('  rankdir=LR;');
  out.writeln('  graph [${_dotAttributes(theme.graphAttributes)}];');
  out.writeln('  node [${_dotAttributes(theme.nodeAttributes)}];');
  out.writeln('  edge [${_dotAttributes(theme.edgeAttributes)}];');

  for (final AgentGraphNode node in graph.nodes) {
    final Map<String, String> attributes = _graphNodeDotAttributes(
      node,
      graph: graph,
      kindById: kindById,
      nodeStatuses: nodeStatuses,
      theme: theme,
    );
    out.writeln('  "${_escapeDot(node.id)}" [${_dotAttributes(attributes)}];');
  }

  for (final (String from, String to) in graph.edges) {
    final Map<String, String> attributes = <String, String>{};
    if (_isToolEdge((from, to), kindById)) {
      attributes['style'] = 'dashed';
    }
    if (highlightPairs.contains((from, to)) ||
        highlightPairs.contains((to, from))) {
      attributes['color'] = 'red';
      attributes['penwidth'] = '2.0';
    }
    final String? label = graph.edgeLabels[(from, to)];
    if (label != null) {
      attributes['label'] = label;
    }

    final String attributeText = attributes.isEmpty
        ? ''
        : ' [${_dotAttributes(attributes)}]';
    out.writeln(
      '  "${_escapeDot(from)}" -> "${_escapeDot(to)}"$attributeText;',
    );
  }

  if (rootAgent is Workflow) {
    final Set<String> terminalNodeIds = _terminalWorkflowNodeIds(rootAgent);
    if (terminalNodeIds.isNotEmpty) {
      out.writeln('  "__END__" [${_dotAttributes(theme.endNodeAttributes)}];');
      for (final String nodeId in terminalNodeIds) {
        out.writeln('  "${_escapeDot(nodeId)}" -> "__END__";');
      }
    }
  }

  out.writeln('}');
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

Map<String, String> _graphNodeDotAttributes(
  AgentGraphNode node, {
  required AgentGraph graph,
  required Map<String, String> kindById,
  required Map<String, NodeStatus> nodeStatuses,
  required _GraphDotTheme theme,
}) {
  final List<(String, String)> outgoingEdges = graph.edges
      .where(((String, String) edge) => edge.$1 == node.id)
      .toList(growable: false);
  final bool isConditional = outgoingEdges.any(
    ((String, String) edge) =>
        graph.edgeLabels[edge] != null && !_isToolEdge(edge, kindById),
  );

  String label = node.caption;
  if (isConditional &&
      !_hasDefaultRoute(outgoingEdges, graph: graph, kindById: kindById)) {
    label = '$label\n[NO DEFAULT]';
  }

  final Map<String, String> attributes = <String, String>{
    'label': label,
    'tooltip': _kindDisplayName(node.kind),
    'fillcolor': _nodeFillColor(node.id, nodeStatuses, theme),
  };

  if (isConditional) {
    attributes.addAll(<String, String>{
      'shape': 'diamond',
      'style': 'filled',
      'height': '1.2',
      'width': '0.8',
      'margin': '0.0,0.0',
    });
  } else if (node.kind == 'join') {
    attributes.addAll(<String, String>{
      'shape': 'oval',
      'style': 'filled',
      'margin': '0.05,0.05',
    });
  } else if (node.kind == 'tool') {
    attributes['style'] = 'rounded,filled,dashed';
  } else {
    attributes['style'] = 'rounded,filled';
  }

  return attributes;
}

bool _hasDefaultRoute(
  List<(String, String)> outgoingEdges, {
  required AgentGraph graph,
  required Map<String, String> kindById,
}) {
  for (final (String, String) edge in outgoingEdges) {
    if (_isToolEdge(edge, kindById)) {
      continue;
    }
    final String? route = graph.edgeLabels[edge];
    if (route == null || route == DEFAULT_ROUTE) {
      return true;
    }
  }
  return false;
}

bool _isToolEdge((String, String) edge, Map<String, String> kindById) {
  return kindById[edge.$2] == 'tool';
}

String _nodeFillColor(
  String nodeId,
  Map<String, NodeStatus> nodeStatuses,
  _GraphDotTheme theme,
) {
  final NodeStatus? status =
      nodeStatuses[nodeId] ?? nodeStatuses[_nodeStateKey(nodeId)];
  final NodeStatus? normalizedStatus = status == NodeStatus.succeeded
      ? NodeStatus.completed
      : status;
  return theme.statusFillColors[normalizedStatus] ??
      theme.nodeAttributes['fillcolor']!;
}

String _nodeStateKey(String nodeId) {
  final int separator = nodeId.lastIndexOf(':');
  if (separator < 0 || separator == nodeId.length - 1) {
    return nodeId;
  }
  return nodeId.substring(separator + 1);
}

Set<String> _terminalWorkflowNodeIds(Workflow workflow) {
  final Set<String> nonTerminalNames = <String>{};
  for (final Edge edge in workflow.edges) {
    if (edge.fromNode != START) {
      nonTerminalNames.add(edge.fromNode);
    }
  }
  for (final BaseNode node in workflow.nodes) {
    nonTerminalNames.addAll(node.dependsOn);
  }

  return <String>{
    for (final BaseNode node in workflow.nodes)
      if (node is! ToolNode && !nonTerminalNames.contains(node.name))
        _workflowNodeId(workflow, node.name),
  };
}

String _kindDisplayName(String kind) {
  return kind
      .split('_')
      .where((String part) => part.isNotEmpty)
      .map((String part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

String _dotAttributes(Map<String, String> attributes) {
  return attributes.entries
      .map(
        (MapEntry<String, String> entry) =>
            '${entry.key}="${_escapeDot(entry.value)}"',
      )
      .join(', ');
}

String _escapeDot(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');
}

class _GraphDotTheme {
  _GraphDotTheme({
    required this.graphAttributes,
    required this.nodeAttributes,
    required this.edgeAttributes,
    required this.endNodeAttributes,
    required this.statusFillColors,
  });

  factory _GraphDotTheme.fromDarkMode(bool darkMode) {
    final String graphBgColor = darkMode ? '#0F172A' : '#F8FAFC';
    final String nodeFillColor = darkMode ? '#1E293B' : '#FFFFFF';
    final String nodeColor = darkMode ? '#475569' : '#94A3B8';
    final String nodeFontColor = darkMode ? '#F8FAFC' : '#0F172A';
    final String edgeColor = darkMode ? '#94A3B8' : '#64748B';
    final String edgeFontColor = darkMode ? '#CBD5E1' : '#475569';
    final String endFillColor = darkMode ? '#DC2626' : '#EF4444';
    final String endColor = darkMode ? '#B91C1C' : '#DC2626';
    final Map<NodeStatus, String> statusFillColors = darkMode
        ? <NodeStatus, String>{
            NodeStatus.completed: '#16A34A',
            NodeStatus.running: '#D97706',
            NodeStatus.failed: '#EF4444',
            NodeStatus.inactive: '#1E293B',
            NodeStatus.waiting: '#9333EA',
            NodeStatus.cancelled: '#475569',
          }
        : <NodeStatus, String>{
            NodeStatus.completed: '#69CB87',
            NodeStatus.running: '#e8b589',
            NodeStatus.failed: 'salmon',
            NodeStatus.inactive: '#FFFFFF',
            NodeStatus.waiting: '#d2a6e0',
            NodeStatus.cancelled: 'lightgray',
          };
    return _GraphDotTheme(
      graphAttributes: <String, String>{
        'bgcolor': graphBgColor,
        'pad': '0.5',
        'nodesep': '0.5',
        'ranksep': '0.8',
        'fontname': 'Helvetica',
        'splines': 'spline',
      },
      nodeAttributes: <String, String>{
        'shape': 'rect',
        'style': 'rounded,filled',
        'fillcolor': nodeFillColor,
        'color': nodeColor,
        'penwidth': '1.5',
        'fontname': 'Helvetica',
        'fontcolor': nodeFontColor,
        'fontsize': '12',
        'margin': '0.25,0.15',
      },
      edgeAttributes: <String, String>{
        'color': edgeColor,
        'penwidth': '1.2',
        'fontname': 'Helvetica',
        'fontcolor': edgeFontColor,
        'fontsize': '10',
        'arrowhead': 'vee',
        'arrowsize': '0.7',
      },
      endNodeAttributes: <String, String>{
        'label': 'END',
        'shape': 'oval',
        'style': 'filled',
        'fillcolor': endFillColor,
        'color': endColor,
        'fontcolor': nodeFontColor,
        'fontname': 'Helvetica-Bold',
        'width': '0.9',
        'fixedsize': 'true',
      },
      statusFillColors: statusFillColors,
    );
  }

  final Map<String, String> graphAttributes;
  final Map<String, String> nodeAttributes;
  final Map<String, String> edgeAttributes;
  final Map<String, String> endNodeAttributes;
  final Map<NodeStatus, String> statusFillColors;
}

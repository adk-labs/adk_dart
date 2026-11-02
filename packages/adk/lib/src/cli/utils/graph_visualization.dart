/// Utility functions for visualizing agent and workflow graphs.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/src/workflow/workflow.dart';

/// Plots the workflow or agent graph with node statuses.
///
/// Returns a [String] when [format] is `'dot'` or `'svg'`, and a [Uint8List]
/// for binary Graphviz output formats.
Object plotWorkflowGraph(
  Map<String, Object?> appInfo, {
  Map<String, Object?>? agentState,
  String format = 'svg',
  bool darkMode = true,
  Uint8List Function(String dotSource, String format)? dotRenderer,
}) {
  final Map<String, Object?> effectiveAgentState =
      agentState ?? <String, Object?>{};
  final Map<String, Object?> rootAgent = _asMap(appInfo['root_agent']);
  Map<String, Object?> graph = _asMap(rootAgent['graph']);
  final bool isWorkflow = graph.isNotEmpty;

  if (!isWorkflow) {
    final String rootName =
        (rootAgent['name'] as String?)?.isNotEmpty == true
            ? rootAgent['name'] as String
            : 'root_agent';
    final List<Object?> tools = _asList(rootAgent['tools']);

    final List<Map<String, Object?>> nodes = <Map<String, Object?>>[
      <String, Object?>{'name': rootName, 'type': 'agent', 'tools': tools},
    ];
    final List<Map<String, Object?>> edges = <Map<String, Object?>>[];

    void traverseSubAgents(
      Map<String, Object?> agentDict,
      String parentName,
    ) {
      for (final Object? rawSub in _asList(agentDict['sub_agents'])) {
        final Map<String, Object?> sub = _asMap(rawSub);
        final String? subName = sub['name'] as String?;
        if (subName != null && subName.isNotEmpty) {
          nodes.add(<String, Object?>{
            'name': subName,
            'type': 'agent',
            'tools': _asList(sub['tools']),
          });
          edges.add(<String, Object?>{
            'from_node': <String, Object?>{'name': parentName},
            'to_node': <String, Object?>{'name': subName},
          });
          traverseSubAgents(sub, subName);
        }
      }
    }

    traverseSubAgents(rootAgent, rootName);
    graph = <String, Object?>{'nodes': nodes, 'edges': edges};
  }

  final Map<String, Object?> nodesState = _asMap(effectiveAgentState['nodes']);

  final String graphBgcolor;
  final String nodeFillcolor;
  final String nodeColor;
  final String nodeFontcolor;
  final String edgeColor;
  final String edgeFontcolor;
  final String startFillcolor;
  final String startColor;
  final String endFillcolor;
  final String endColor;
  final Map<NodeStatus, String> statusColors;

  if (darkMode) {
    graphBgcolor = '#0F172A';
    nodeFillcolor = '#1E293B';
    nodeColor = '#475569';
    nodeFontcolor = '#F8FAFC';
    edgeColor = '#94A3B8';
    edgeFontcolor = '#CBD5E1';
    startFillcolor = '#059669';
    startColor = '#047857';
    endFillcolor = '#DC2626';
    endColor = '#B91C1C';
    statusColors = <NodeStatus, String>{
      NodeStatus.completed: '#16A34A',
      NodeStatus.running: '#D97706',
      NodeStatus.failed: '#EF4444',
      NodeStatus.inactive: '#1E293B',
      NodeStatus.waiting: '#9333EA',
      NodeStatus.cancelled: '#475569',
    };
  } else {
    graphBgcolor = '#F8FAFC';
    nodeFillcolor = '#FFFFFF';
    nodeColor = '#94A3B8';
    nodeFontcolor = '#0F172A';
    edgeColor = '#64748B';
    edgeFontcolor = '#475569';
    startFillcolor = '#10B981';
    startColor = '#059669';
    endFillcolor = '#EF4444';
    endColor = '#DC2626';
    statusColors = <NodeStatus, String>{
      NodeStatus.completed: '#69CB87',
      NodeStatus.running: '#e8b589',
      NodeStatus.failed: 'salmon',
      NodeStatus.inactive: '#FFFFFF',
      NodeStatus.waiting: '#d2a6e0',
      NodeStatus.cancelled: 'lightgray',
    };
  }

  final StringBuffer dot = StringBuffer();
  dot.writeln('// Workflow Visualization');
  dot.writeln('digraph {');
  dot.writeln(
    '\tgraph [bgcolor="${_escapeDot(graphBgcolor)}" fontname=Helvetica '
    'nodesep=0.5 pad=0.5 ranksep=0.8 splines=spline]',
  );
  dot.writeln(
    '\tnode [color="${_escapeDot(nodeColor)}" '
    'fillcolor="${_escapeDot(nodeFillcolor)}" fontcolor="${_escapeDot(nodeFontcolor)}" '
    'fontname=Helvetica fontsize=12 margin="0.25,0.15" penwidth=1.5 '
    'shape=rect style="rounded,filled"]',
  );
  dot.writeln(
    '\tedge [arrowhead=vee arrowsize=0.7 color="${_escapeDot(edgeColor)}" '
    'fontcolor="${_escapeDot(edgeFontcolor)}" fontname=Helvetica fontsize=10 '
    'penwidth=1.2]',
  );

  final List<Map<String, Object?>> nodes = _asList(
    graph['nodes'],
  ).map(_asMap).toList();
  final List<Map<String, Object?>> edges = _asList(
    graph['edges'],
  ).map(_asMap).toList();

  final Map<String, Map<String, Object?>> toolNodes =
      <String, Map<String, Object?>>{};
  final List<Map<String, Object?>> toolEdges = <Map<String, Object?>>[];
  for (final Map<String, Object?> node in nodes) {
    final String? nodeName = node['name'] as String?;
    if (nodeName == null || nodeName.isEmpty || nodeName == '__START__') {
      continue;
    }

    final List<Object?> tools = _asList(node['tools']);
    for (final Object? tool in tools) {
      final String? toolName = tool is Map
          ? '${tool['name'] ?? ''}'
          : (tool == null ? null : '$tool');
      if (toolName != null && toolName.isNotEmpty) {
        if (!toolNodes.containsKey(toolName)) {
          final String toolType = tool is Map
              ? '${tool['type'] ?? 'tool'}'
              : 'tool';
          toolNodes[toolName] = <String, Object?>{
            'name': toolName,
            'type': toolType,
          };
        }
        toolEdges.add(<String, Object?>{
          'from_node': <String, Object?>{'name': nodeName},
          'to_node': <String, Object?>{'name': toolName},
          'is_tool_edge': true,
        });
      }
    }
  }

  for (final Map<String, Object?> toolNode in toolNodes.values) {
    final String? toolName = toolNode['name'] as String?;
    if (!nodes.any((Map<String, Object?> on) => on['name'] == toolName)) {
      nodes.add(toolNode);
    }
  }
  edges.addAll(toolEdges);

  const Map<String, (String, String)> icons = <String, (String, String)>{
    'agent': ('✦', '#42A5F5'),
    'workflow': ('⊷', '#9333EA'),
    'function': ('ƒ', '#10B981'),
    'join': ('⌵', '#F59E0B'),
    'tool': ('🔧', '#6B7280'),
  };

  for (final Map<String, Object?> node in nodes) {
    final String? nodeName = node['name'] as String?;
    if (nodeName == null || nodeName.isEmpty || nodeName == '__START__') {
      continue;
    }

    final List<Map<String, Object?>> outgoingEdges = edges
        .where(
          (Map<String, Object?> e) =>
              _edgeEndpointName(e['from_node']) == nodeName,
        )
        .toList(growable: false);
    final bool isConditional = outgoingEdges.any(
      (Map<String, Object?> e) =>
          e['route'] != null && '${e['route']}'.isNotEmpty,
    );

    final Map<String, Object?> nodeData = _asMap(nodesState[nodeName]);
    final NodeStatus status = _parseNodeStatus(nodeData['status']);
    final String fillcolor = statusColors[status] ?? nodeFillcolor;

    final String nodeType = (node['type'] as String?) ?? 'node';
    final (String, String)? iconData = icons[nodeType];
    final String typeDisplay = _titleCase(nodeType);

    String nodeLabel;
    bool isHtmlLabel = false;
    if (iconData != null) {
      final (String icon, String color) = iconData;
      final String escapedName = _htmlEscape(nodeName);
      nodeLabel =
          '<<FONT COLOR="$color" POINT-SIZE="14">$icon</FONT> $escapedName>';
      isHtmlLabel = true;
    } else {
      nodeLabel = nodeName;
    }

    if (isConditional) {
      final bool hasDefault = outgoingEdges
          .where((Map<String, Object?> e) => e['is_tool_edge'] != true)
          .any((Map<String, Object?> e) {
            final Object? route = e['route'];
            return route == null || '$route'.isEmpty || route == '__DEFAULT__';
          });
      if (!hasDefault) {
        if (iconData != null) {
          final (String icon, String color) = iconData;
          final String escapedName = _htmlEscape(nodeName);
          nodeLabel =
              '<<FONT COLOR="$color" POINT-SIZE="14">$icon</FONT>'
              ' $escapedName<br/><br/><FONT POINT-SIZE="10">⚠️ [NO'
              ' DEFAULT]</FONT>>';
          isHtmlLabel = true;
        } else {
          final String escapedLabel = _htmlEscape(nodeLabel);
          nodeLabel =
              '<$escapedLabel<br/><br/><font point-size=\'10\'>⚠️ [NO'
              ' DEFAULT]</font>>';
          isHtmlLabel = true;
        }
      }

      dot.writeln(
        '\t${_dotId(nodeName)} [label=${_dotLabelValue(nodeLabel, isHtml: isHtmlLabel)} '
        'fillcolor="${_escapeDot(fillcolor)}" height=1.2 margin="0.0,0.0" '
        'shape=diamond style=filled tooltip="${_escapeDot(typeDisplay)}" width=0.8]',
      );
    } else if (nodeType == 'join') {
      dot.writeln(
        '\t${_dotId(nodeName)} [label=${_dotLabelValue(nodeLabel, isHtml: isHtmlLabel)} '
        'fillcolor="${_escapeDot(fillcolor)}" margin="0.05,0.05" '
        'shape=oval style=filled tooltip="${_escapeDot(typeDisplay)}"]',
      );
    } else if (nodeType == 'tool') {
      dot.writeln(
        '\t${_dotId(nodeName)} [label=${_dotLabelValue(nodeLabel, isHtml: isHtmlLabel)} '
        'fillcolor="${_escapeDot(fillcolor)}" style="rounded,filled,dashed" '
        'tooltip="${_escapeDot(typeDisplay)}"]',
      );
    } else {
      dot.writeln(
        '\t${_dotId(nodeName)} [label=${_dotLabelValue(nodeLabel, isHtml: isHtmlLabel)} '
        'fillcolor="${_escapeDot(fillcolor)}" style="rounded,filled" '
        'tooltip="${_escapeDot(typeDisplay)}"]',
      );
    }
  }

  for (final Map<String, Object?> edge in edges) {
    final String? fromNode = _edgeEndpointName(edge['from_node']);
    final String? toNode = _edgeEndpointName(edge['to_node']);

    if (fromNode == '__START__') {
      dot.writeln(
        '\t__START__ [label=START color="${_escapeDot(startColor)}" '
        'fillcolor="${_escapeDot(startFillcolor)}" fixedsize=true '
        'fontcolor="${_escapeDot(nodeFontcolor)}" fontname="Helvetica-Bold" '
        'shape=oval style=filled width=0.9]',
      );
    }

    if (fromNode != null &&
        fromNode.isNotEmpty &&
        toNode != null &&
        toNode.isNotEmpty) {
      if (edge['is_tool_edge'] == true) {
        dot.writeln(
          '\t${_dotId(fromNode)} -> ${_dotId(toNode)} '
          '[color="${_escapeDot(edgeColor)}" style=dashed]',
        );
      } else {
        final Object? route = edge['route'];
        final String label = (route != null && '$route'.isNotEmpty)
            ? '  $route'
            : '';
        dot.writeln(
          '\t${_dotId(fromNode)} -> ${_dotId(toNode)} '
          '[label="${_escapeDot(label)}"]',
        );
      }
    }
  }

  final List<String> terminalNodes = <String>[];
  for (final Map<String, Object?> node in nodes) {
    final String? nodeName = node['name'] as String?;
    if (nodeName == null ||
        nodeName.isEmpty ||
        nodeName == '__START__' ||
        nodeName == '__END__') {
      continue;
    }
    if (node['type'] == 'tool') {
      continue;
    }

    final List<Map<String, Object?>> outgoingEdges = edges
        .where(
          (Map<String, Object?> e) =>
              _edgeEndpointName(e['from_node']) == nodeName &&
              e['is_tool_edge'] != true,
        )
        .toList(growable: false);
    if (outgoingEdges.isEmpty) {
      terminalNodes.add(nodeName);
    }
  }

  if (isWorkflow && terminalNodes.isNotEmpty) {
    dot.writeln(
      '\t__END__ [label=END color="${_escapeDot(endColor)}" '
      'fillcolor="${_escapeDot(endFillcolor)}" fixedsize=true '
      'fontcolor="${_escapeDot(nodeFontcolor)}" fontname="Helvetica-Bold" '
      'shape=oval style=filled width=0.9]',
    );
    for (final String tNode in terminalNodes) {
      dot.writeln('\t${_dotId(tNode)} -> __END__');
    }
  }

  dot.writeln('}');
  final String dotSource = dot.toString();

  if (format == 'dot') {
    return dotSource;
  }

  final Uint8List renderedBytes = dotRenderer != null
      ? dotRenderer(dotSource, format)
      : _pipeGraphvizDot(dotSource, format);
  if (format == 'svg') {
    return utf8.decode(renderedBytes);
  }
  return renderedBytes;
}

Uint8List _pipeGraphvizDot(String dotSource, String format) {
  try {
    final ProcessResult result = Process.runSync(
      'dot',
      <String>['-T$format'],
      stdoutEncoding: null,
    );
    // Process.runSync does not support stdin directly; use a temp file if `dot` is available.
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'adk_graphviz_',
    );
    try {
      final File dotFile = File(
        '${tempDir.path}${Platform.pathSeparator}graph.dot',
      );
      dotFile.writeAsStringSync(dotSource);
      final ProcessResult fileResult = Process.runSync(
        'dot',
        <String>['-T$format', dotFile.path],
        stdoutEncoding: null,
      );
      if (fileResult.exitCode == 0 && fileResult.stdout is List<int>) {
        return Uint8List.fromList(fileResult.stdout as List<int>);
      }
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
    if (result.exitCode == 0 && result.stdout is List<int>) {
      return Uint8List.fromList(result.stdout as List<int>);
    }
  } on Object {
    // Fall back when Graphviz `dot` binary is not installed on the host.
  }

  if (format == 'svg') {
    final String escaped = _htmlEscape(dotSource);
    return Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg"><desc>$escaped</desc></svg>',
      ),
    );
  }
  return Uint8List.fromList(utf8.encode(dotSource));
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  return <String, Object?>{};
}

List<Object?> _asList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}

String? _edgeEndpointName(Object? endpoint) {
  if (endpoint is String) {
    return endpoint;
  }
  if (endpoint is Map) {
    final Object? name = endpoint['name'];
    return name is String ? name : (name == null ? null : '$name');
  }
  return null;
}

NodeStatus _parseNodeStatus(Object? rawStatus) {
  if (rawStatus is NodeStatus) {
    return rawStatus == NodeStatus.succeeded
        ? NodeStatus.completed
        : rawStatus;
  }
  if (rawStatus is String) {
    final String normalized = rawStatus.trim().toLowerCase();
    for (final NodeStatus candidate in NodeStatus.values) {
      if (candidate.name.toLowerCase() == normalized) {
        return candidate == NodeStatus.succeeded
            ? NodeStatus.completed
            : candidate;
      }
    }
  }
  return NodeStatus.inactive;
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value
      .split('_')
      .map(
        (String word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join('_');
}

String _htmlEscape(String input) {
  return const HtmlEscape().convert(input);
}

String _escapeDot(String input) {
  return input.replaceAll('\\', r'\\').replaceAll('"', r'\"');
}

String _dotId(String id) {
  if (RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(id)) {
    return id;
  }
  return '"${_escapeDot(id)}"';
}

String _dotLabelValue(String label, {required bool isHtml}) {
  if (isHtml) {
    return label;
  }
  return '"${_escapeDot(label)}"';
}

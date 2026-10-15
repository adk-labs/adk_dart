/// Tool adapter that executes a workflow [BaseNode] as a standard ADK tool.
library;

import 'dart:convert';

import '../agents/base_agent.dart';
import '../agents/llm_agent.dart';
import '../errors/input_validation_error.dart';
import '../models/llm_request.dart';
import '../workflow/workflow.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// Returns the entry nodes of [workflow] that can receive `START` input.
///
/// Mirrors upstream `_start_entry_nodes`: selects nodes connected from [START]
/// (or nodes without incoming edges when no [START] edges exist) and excludes
/// [JoinNode] instances or nodes with explicit `dependsOn` predecessors.
List<BaseNode> startEntryNodes(Workflow workflow) {
  final Map<String, BaseNode> byName = <String, BaseNode>{
    for (final BaseNode current in workflow.nodes) current.name: current,
  };
  final List<String> candidateNames;
  if (workflow.edges.isEmpty) {
    candidateNames = byName.keys.toList(growable: false);
  } else {
    final Set<String> targets = <String>{};
    final Set<String> startTargets = <String>{};
    for (final Edge edge in workflow.edges) {
      if (edge.fromNode == START) {
        startTargets.add(edge.toNode);
      } else {
        targets.add(edge.toNode);
      }
    }
    candidateNames = <String>[
      for (final String name in byName.keys)
        if (!targets.contains(name) || startTargets.contains(name)) name,
    ];
  }
  return <BaseNode>[
    for (final String name in candidateNames)
      if (byName[name] != null &&
          byName[name]!.dependsOn.isEmpty &&
          byName[name] is! JoinNode)
        byName[name]!,
  ];
}

/// Resolves the effective input schema for [nodeLike], if any.
///
/// Inspects explicit `inputSchema` fields, [AgentNode] inner agents (including
/// nested [Workflow] entry nodes when all entry nodes share an identical
/// non-null schema), and [ToolNode] function declarations.
Object? resolveNodeInputSchema(Object nodeLike) {
  final Object? directSchema = _readDynamicInputSchema(nodeLike);
  if (directSchema != null) {
    return directSchema;
  }
  if (nodeLike is AgentNode) {
    final BaseAgent innerAgent = nodeLike.agent;
    if (innerAgent is LlmAgent) {
      return innerAgent.inputSchema;
    }
    if (innerAgent is Workflow) {
      return resolveNodeInputSchema(innerAgent);
    }
    return _readDynamicInputSchema(innerAgent);
  }
  if (nodeLike is Workflow) {
    final List<BaseNode> entryNodes = startEntryNodes(nodeLike);
    if (entryNodes.isEmpty) {
      return null;
    }
    final List<Object?> schemas = <Object?>[];
    for (final BaseNode entryNode in entryNodes) {
      final Object? entrySchema = resolveNodeInputSchema(entryNode);
      if (entrySchema == null) {
        return null;
      }
      schemas.add(entrySchema);
    }
    final Object? first = schemas.first;
    for (int i = 1; i < schemas.length; i += 1) {
      if (!_schemasEqual(first, schemas[i])) {
        return null;
      }
    }
    return first;
  }
  if (nodeLike is ToolNode) {
    return nodeLike.tool.getDeclaration()?.parameters;
  }
  return null;
}

Object? _readDynamicInputSchema(Object target) {
  try {
    final dynamic dynamicTarget = target;
    return dynamicTarget.inputSchema;
  } on NoSuchMethodError {
    return null;
  }
}

bool _schemasEqual(Object? a, Object? b) {
  if (identical(a, b) || a == b) {
    return true;
  }
  try {
    return jsonEncode(a) == jsonEncode(b);
  } catch (_) {
    return false;
  }
}

/// A tool wrapper that executes a [BaseNode] (e.g. a workflow function node or
/// tool node) as a standard ADK [BaseTool].
///
/// This is the Dart analog of upstream's `NodeTool` ("Workflow as Tool").
/// It allows an individual node to be wrapped and invoked by an [LlmAgent] via
/// function calling. The wrapped node is executed in an isolated single-node
/// workflow (`START -> node`) and its output is returned to the caller.
///
/// [BaseAgent] instances (including `Workflow`, which is an agent in this port)
/// cannot be wrapped: agents should be composed as sub-agents or via
/// `AgentTool`. Passing one throws an [ArgumentError].
class NodeTool extends BaseTool {
  /// Creates a tool that executes [node].
  ///
  /// [name] and [description] default to the wrapped node's own values. A
  /// non-empty description is required so the model understands the tool.
  NodeTool({
    required this.node,
    String? name,
    String? description,
    this.inputSchema,
    this.outputSchema,
  }) : super(
         name: name ?? node.name,
         description: description == null || description.isEmpty
             ? (node.description.isEmpty
                   ? 'Executes the node: ${node.name}'
                   : node.description)
             : description,
         isLongRunning: true,
       ) {
    if (node is BaseAgent) {
      throw ArgumentError(
        "Agent '${(node as BaseAgent).name}' cannot be used directly as a tool. "
        'Agents should be invoked as sub-agents.',
      );
    }
  }

  /// The node executed by this tool.
  final BaseNode node;

  /// Optional JSON schema for input parameters.
  final Map<String, dynamic>? inputSchema;

  /// Optional JSON schema for returned outputs.
  final Map<String, dynamic>? outputSchema;

  @override
  FunctionDeclaration? getDeclaration() {
    final Object? resolvedSchema = inputSchema ?? resolveNodeInputSchema(node);
    Map<String, dynamic>? parameters;
    if (resolvedSchema is Map) {
      final Map<String, dynamic> schemaMap = Map<String, dynamic>.from(
        resolvedSchema,
      );
      if (schemaMap['type'] == 'object' ||
          schemaMap.containsKey('properties')) {
        parameters = schemaMap;
      } else {
        parameters = <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{'input': schemaMap},
          'required': <String>['input'],
        };
      }
    } else if (resolvedSchema is String && resolvedSchema.isNotEmpty) {
      parameters = <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'input': <String, dynamic>{
            'type': resolvedSchema,
            'description': 'Input for the node.',
          },
        },
      };
    }

    return FunctionDeclaration(
      name: name,
      description: description,
      parameters:
          parameters ??
          <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'request': <String, dynamic>{'type': 'string'},
            },
          },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? resolvedSchema = inputSchema ?? resolveNodeInputSchema(node);
    final bool isObjectSchema =
        resolvedSchema is Map &&
        (resolvedSchema['type'] == 'object' ||
            resolvedSchema.containsKey('properties'));
    final Map<Object?, Object?>? schemaProps =
        isObjectSchema && resolvedSchema['properties'] is Map
        ? resolvedSchema['properties'] as Map<Object?, Object?>
        : null;

    Object? nodeInput;
    if (isObjectSchema) {
      if (args.length == 1 &&
          args.containsKey('input') &&
          (schemaProps == null || !schemaProps.containsKey('input'))) {
        nodeInput = args['input'];
      } else if (args.length == 1 &&
          args.containsKey('request') &&
          (schemaProps == null || !schemaProps.containsKey('request'))) {
        nodeInput = args['request'];
      } else {
        nodeInput = args;
      }
    } else if (args.length == 1 && args.containsKey('request')) {
      nodeInput = args['request'];
    } else if (args.length == 1 && args.containsKey('input')) {
      nodeInput = args['input'];
    } else {
      nodeInput = args;
    }

    try {
      if (resolvedSchema != null) {
        nodeInput = validateNodeData(resolvedSchema, nodeInput);
      } else if (node is AgentNode && (node as AgentNode).agent is Workflow) {
        final Workflow innerWorkflow = (node as AgentNode).agent as Workflow;
        for (final BaseNode entryNode in startEntryNodes(innerWorkflow)) {
          final Object? entrySchema = resolveNodeInputSchema(entryNode);
          if (entrySchema != null) {
            validateNodeData(entrySchema, nodeInput);
          }
        }
      }

      final Workflow workflow = Workflow(
        name: '${name}_node_tool',
        description: description,
        nodes: <BaseNode>[node],
        edges: <Edge>[Edge(fromNode: START, toNode: node.name)],
      );
      final WorkflowResult result = await workflow.runWorkflow(
        input: nodeInput,
      );
      return result.outputs[node.name];
    } on InputValidationError catch (error) {
      return <String, Object?>{'error': '$error'};
    } catch (error) {
      return 'Error running node $name: $error';
    }
  }
}

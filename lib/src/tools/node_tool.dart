/// Tool adapter that executes a workflow [BaseNode] as a standard ADK tool.
library;

import '../agents/base_agent.dart';
import '../models/llm_request.dart';
import '../workflow/workflow.dart';
import 'base_tool.dart';
import 'tool_context.dart';

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
  NodeTool({required this.node, String? name, String? description})
    : super(
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
        "Agent '${(node as BaseAgent).name}' cannot be wrapped as a NodeTool. "
        'Agents should be invoked as sub-agents instead.',
      );
    }
  }

  /// The node executed by this tool.
  final BaseNode node;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
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
    // Prefer an explicit single-value `request` argument; otherwise pass the
    // full argument map as the node input.
    final Object? nodeInput = args.length == 1 && args.containsKey('request')
        ? args['request']
        : args;

    try {
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
    } catch (error) {
      return 'Error running node $name: $error';
    }
  }
}

/// Tool adapter that wraps and executes an entire [Workflow] graph.
library;

import '../models/llm_request.dart';
import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import 'workflow.dart';

/// A tool wrapper that executes a complete multi-node [Workflow] graph as a
/// standard ADK [BaseTool].
///
/// This provides the "Workflow as Tool" capability, allowing parent agents or
/// orchestrators to call sub-workflows directly via function calling.
class WorkflowTool extends BaseTool {
  /// Creates a tool wrapper for [workflow].
  WorkflowTool({
    required this.workflow,
    String? name,
    String? description,
    this.inputSchema,
    this.outputSchema,
  }) : super(
         name: name ?? workflow.name,
         description:
             description == null || description.isEmpty
                 ? (workflow.description.isEmpty
                     ? 'Executes workflow: ${workflow.name}'
                     : workflow.description)
                 : description,
         isLongRunning: true,
       );

  /// The underlying workflow graph executed by this tool.
  final Workflow workflow;

  /// Optional JSON schema for input parameters.
  final Map<String, dynamic>? inputSchema;

  /// Optional JSON schema for returned outputs.
  final Map<String, dynamic>? outputSchema;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters:
          inputSchema ??
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
    final Object? workflowInput =
        args.length == 1 && args.containsKey('request')
            ? args['request']
            : args;

    try {
      final WorkflowResult result = await workflow.runWorkflow(
        input: workflowInput,
      );
      return result.outputs;
    } catch (error) {
      return 'Error running workflow $name: $error';
    }
  }
}

/// Tool that pauses execution and asks the user for additional input.
library;

import '../flows/llm_flows/functions.dart';
import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// Long-running tool that requests human input before execution continues.
class RequestInputTool extends BaseTool {
  /// Creates a request-input tool.
  RequestInputTool()
    : super(
        name: requestInputFunctionCallName,
        description:
            'Ask the user a question and wait for their response before proceeding.',
        isLongRunning: true,
      );

  @override
  FunctionDeclaration getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'message': <String, dynamic>{
            'type': 'string',
            'description': 'The question or prompt to display to the user.',
          },
          'response_schema': <String, dynamic>{
            'type': 'object',
            'description':
                'Optional JSON Schema describing the expected user response.',
          },
        },
        'required': <String>['message'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return null;
  }
}

/// Default request-input tool instance.
final RequestInputTool requestInput = RequestInputTool();

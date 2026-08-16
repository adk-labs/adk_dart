/// A long-running tool that presents a list of options to the user and awaits their selection.
library;

import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

const String getUserChoiceFunctionName = 'get_user_choice';

/// Long-running function tool that prompts user to select from a list of options.
class GetUserChoiceTool extends BaseTool {
  /// Creates a get_user_choice tool instance.
  GetUserChoiceTool()
      : super(
          name: getUserChoiceFunctionName,
          description:
              'Presents a list of options to the user and awaits their selection.',
        );

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'options': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{'type': 'string'},
            'description': 'List of options to present to the user.',
          },
        },
        'required': <String>['options'],
      },
    );
  }

  /// Invokes the tool synchronously given [options] and [context].
  String? call(List<String> options, ToolContext context) {
    context.actions.skipSummarization = true;
    return null;
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    toolContext.actions.skipSummarization = true;
    return null;
  }
}

/// Global singleton instance of [GetUserChoiceTool].
final GetUserChoiceTool getUserChoice = GetUserChoiceTool();

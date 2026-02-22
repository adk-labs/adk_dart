import '../models/llm_request.dart';
import 'function_tool.dart';
import 'tool_context.dart';

Object? transferToAgent(Map<String, dynamic> args, ToolContext toolContext) {
  final String? agentName =
      args['agent_name'] as String? ?? args['agentName'] as String?;
  if (agentName == null || agentName.isEmpty) {
    throw ArgumentError('agent_name is required for transfer_to_agent.');
  }
  toolContext.actions.transferToAgent = agentName;
  return null;
}

class TransferToAgentTool extends FunctionTool {
  TransferToAgentTool({required List<String> agentNames})
    : _agentNames = List<String>.from(agentNames),
      super(
        func: transferToAgent,
        name: 'transfer_to_agent',
        description:
            'Transfer the question to another agent when another agent is more suitable.',
      );

  final List<String> _agentNames;

  @override
  FunctionDeclaration? getDeclaration() {
    final FunctionDeclaration? declaration = super.getDeclaration();
    if (declaration == null) {
      return null;
    }

    final Map<String, dynamic> parameters = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'agent_name': <String, dynamic>{
          'type': 'string',
          'enum': List<String>.from(_agentNames),
        },
      },
      'required': <String>['agent_name'],
    };

    return declaration.copyWith(parameters: parameters);
  }
}

/// Tool helpers for agent-to-agent transfer actions.
library;

import '../models/llm_request.dart';
import 'function_tool.dart';
import 'tool_context.dart';

const String _docstringWithoutReason =
    'Transfer the query to another agent.\n'
    '\n'
    'Use this tool to hand off control to another agent that is more '
    "suitable to answer the user's query according to the agent's "
    'description.';

const String _docstringWithReason =
    'Transfer the query to another agent.\n'
    '\n'
    'Use this tool to hand off control to another agent that is more '
    "suitable to answer the user's query according to the agent's "
    'description.\n'
    '\n'
    'Args:\n'
    '  agent_name: the agent name to transfer to.\n'
    '  transfer_reason: the reason for transferring to the target agent.';

/// Built-in function implementation that requests agent transfer.
Object? transferToAgent(Map<String, dynamic> args, ToolContext toolContext) {
  final String? agentName =
      args['agent_name'] as String? ?? args['agentName'] as String?;
  if (agentName == null || agentName.isEmpty) {
    throw ArgumentError('agent_name is required for transfer_to_agent.');
  }
  final String? transferReason =
      args['transfer_reason'] as String? ?? args['transferReason'] as String?;
  toolContext.actions.transferToAgent = agentName;
  toolContext.actions.transferReason =
      (transferReason != null && transferReason.isNotEmpty)
          ? transferReason
          : null;
  return null;
}

/// Function tool that lets agents transfer execution to peer agents.
class TransferToAgentTool extends FunctionTool {
  /// Creates a transfer tool constrained to [agentNames].
  TransferToAgentTool({
    required List<String> agentNames,
    this.includeTransferReason = false,
  })  : _agentNames = List<String>.from(agentNames),
        super(
          func: transferToAgent,
          name: 'transfer_to_agent',
          description: includeTransferReason
              ? _docstringWithReason
              : _docstringWithoutReason,
        );

  final List<String> _agentNames;

  /// Whether to include the transfer_reason parameter in the tool declaration.
  final bool includeTransferReason;

  @override
  /// Returns declaration schema restricted to configured agent names.
  FunctionDeclaration? getDeclaration() {
    final FunctionDeclaration? declaration = super.getDeclaration();
    if (declaration == null) {
      return null;
    }

    final Map<String, dynamic> properties = <String, dynamic>{
      'agent_name': <String, dynamic>{
        'type': 'string',
        'enum': List<String>.from(_agentNames),
      },
    };

    if (includeTransferReason) {
      properties['transfer_reason'] = <String, dynamic>{
        'type': 'string',
      };
    }

    final Map<String, dynamic> parameters = <String, dynamic>{
      'type': 'object',
      'properties': properties,
      'required': <String>['agent_name'],
    };

    return declaration.copyWith(
      description: includeTransferReason
          ? _docstringWithReason
          : _docstringWithoutReason,
      parameters: parameters,
    );
  }
}

import '../../agents/base_agent.dart';
import '../../agents/context.dart';
import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../tools/tool_context.dart';
import '../../tools/transfer_to_agent_tool.dart';
import 'base_llm_flow.dart';

class AgentTransferLlmRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final BaseAgent agent = invocationContext.agent;
    if (agent is! LlmAgent) {
      return;
    }

    final List<BaseAgent> transferTargets = getTransferTargets(agent);
    if (transferTargets.isEmpty) {
      return;
    }

    final TransferToAgentTool transferToAgentTool = TransferToAgentTool(
      agentNames: transferTargets
          .map((BaseAgent target) => target.name)
          .toList(growable: false),
    );

    llmRequest.appendInstructions(<String>[
      buildTransferInstructions(
        transferToAgentTool.name,
        agent,
        transferTargets,
      ),
    ]);

    final ToolContext toolContext = Context(invocationContext);
    await transferToAgentTool.processLlmRequest(
      toolContext: toolContext,
      llmRequest: llmRequest,
    );
  }
}

String buildTargetAgentsInfo(BaseAgent targetAgent) {
  return '''
Agent name: ${targetAgent.name}
Agent description: ${targetAgent.description}
''';
}

const String lineBreak = '\n';

String buildTransferInstructionBody(
  String toolName,
  List<BaseAgent> targetAgents,
) {
  final List<String> availableAgentNames =
      targetAgents.map((BaseAgent target) => target.name).toList()..sort();
  final String formattedAgentNames = availableAgentNames
      .map((String name) => '`$name`')
      .join(', ');

  return '''
You have a list of other agents to transfer to:

${targetAgents.map(buildTargetAgentsInfo).join(lineBreak)}

If you are the best to answer the question according to your description,
you can answer it.

If another agent is better for answering the question according to its
description, call `$toolName` function to transfer the question to that
agent. When transferring, do not generate any text other than the function
call.

**NOTE**: the only available agents for `$toolName` function are
$formattedAgentNames.
''';
}

String buildTransferInstructions(
  String toolName,
  LlmAgent agent,
  List<BaseAgent> targetAgents,
) {
  String instruction = buildTransferInstructionBody(toolName, targetAgents);

  if (agent.parentAgent != null && !agent.disallowTransferToParent) {
    instruction +=
        '''
If neither you nor the other agents are best for the question, transfer to your parent agent ${agent.parentAgent!.name}.
''';
  }

  return instruction;
}

List<BaseAgent> getTransferTargets(LlmAgent agent) {
  final List<BaseAgent> result = <BaseAgent>[];
  result.addAll(agent.subAgents);

  final BaseAgent? parent = agent.parentAgent;
  if (parent is! LlmAgent) {
    return result;
  }

  if (!agent.disallowTransferToParent) {
    result.add(parent);
  }

  if (!agent.disallowTransferToPeers) {
    result.addAll(
      parent.subAgents.where(
        (BaseAgent peerAgent) => peerAgent.name != agent.name,
      ),
    );
  }

  return result;
}

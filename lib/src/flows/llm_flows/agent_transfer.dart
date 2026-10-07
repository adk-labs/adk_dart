/// LLM flow processor that handles transfer-to-agent actions.
library;

import 'dart:async';

import '../../agents/base_agent.dart';
import '../../agents/context.dart';
import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../agents/managed_agent.dart';
import '../../agents/remote_a2a_agent.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../tools/tool_context.dart';
import '../../tools/transfer_to_agent_tool.dart';
import 'base_llm_flow.dart';

/// Metadata describing an agent transfer target.
class TransferTargetInfo {
  /// Creates transfer target metadata.
  const TransferTargetInfo({required this.name, required this.description});

  /// Target agent name.
  final String name;

  /// Target agent description.
  final String description;
}

/// Resolves and caches transfer target metadata for [targetAgent].
Future<TransferTargetInfo> buildTransferTargetInfo(
  BaseAgent targetAgent,
  InvocationContext context,
) async {
  final String cacheKey = '_transfer_target_info_${targetAgent.name}';
  final Object? cached = context.privateMetadata[cacheKey];
  if (cached is TransferTargetInfo) {
    return cached;
  }

  String description = targetAgent.description;
  if (targetAgent is RemoteA2aAgent) {
    try {
      description = await targetAgent
          .getTransferDescription(context)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      description = targetAgent.description;
    }
  }

  final TransferTargetInfo info = TransferTargetInfo(
    name: targetAgent.name,
    description: description,
  );
  context.privateMetadata[cacheKey] = info;
  return info;
}

/// Injects transfer instructions/tool declarations into LLM requests.
class AgentTransferLlmRequestProcessor extends BaseLlmRequestProcessor {
  /// Appends transfer guidance and transfer tool configuration.
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

    if (!_usesTaskTransferMode(agent)) {
      final List<TransferTargetInfo> targetInfos = await Future.wait(
        transferTargets.map(
          (BaseAgent target) =>
              buildTransferTargetInfo(target, invocationContext),
        ),
      );
      final String instructions = buildTransferInstructionsFromInfos(
        transferToAgentTool.name,
        agent,
        targetInfos,
      );
      if (instructions.isNotEmpty) {
        llmRequest.appendInstructions(<String>[instructions]);
      }
    }

    final ToolContext toolContext = Context(invocationContext);
    await transferToAgentTool.processLlmRequest(
      toolContext: toolContext,
      llmRequest: llmRequest,
    );
  }
}

/// Builds one target-agent description block.
String buildTargetAgentsInfo(BaseAgent targetAgent) {
  return buildTargetAgentsInfoFromTargetInfo(
    TransferTargetInfo(
      name: targetAgent.name,
      description: targetAgent.description,
    ),
  );
}

/// Builds one target-agent description block from [targetInfo].
String buildTargetAgentsInfoFromTargetInfo(TransferTargetInfo targetInfo) {
  return '''
Agent name: ${targetInfo.name}
Agent description: ${targetInfo.description}
''';
}

/// Line break token used when composing multi-agent instructions.
const String lineBreak = '\n';

/// Builds shared transfer instruction text for [targetAgents].
String buildTransferInstructionBody(
  String toolName,
  List<BaseAgent> targetAgents,
) {
  return buildTransferInstructionBodyFromInfos(
    toolName,
    targetAgents
        .map(
          (BaseAgent target) => TransferTargetInfo(
            name: target.name,
            description: target.description,
          ),
        )
        .toList(growable: false),
  );
}

/// Builds shared transfer instruction text for resolved [targetInfos].
String buildTransferInstructionBodyFromInfos(
  String toolName,
  List<TransferTargetInfo> targetInfos,
) {
  final List<String> availableAgentNames =
      targetInfos.map((TransferTargetInfo target) => target.name).toList()
        ..sort();
  final String formattedAgentNames = availableAgentNames
      .map((String name) => '`$name`')
      .join(', ');

  return '''
You have a list of other agents to transfer to:

${targetInfos.map(buildTargetAgentsInfoFromTargetInfo).join(lineBreak)}

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

/// Builds full transfer instructions for [agent].
String buildTransferInstructions(
  String toolName,
  LlmAgent agent,
  List<BaseAgent> targetAgents,
) {
  return buildTransferInstructionsFromInfos(
    toolName,
    agent,
    targetAgents
        .map(
          (BaseAgent target) => TransferTargetInfo(
            name: target.name,
            description: target.description,
          ),
        )
        .toList(growable: false),
  );
}

/// Builds full transfer instructions for [agent] from resolved [targetInfos].
String buildTransferInstructionsFromInfos(
  String toolName,
  LlmAgent agent,
  List<TransferTargetInfo> targetInfos,
) {
  if (_usesTaskTransferMode(agent)) {
    return '';
  }
  String instruction = buildTransferInstructionBodyFromInfos(
    toolName,
    targetInfos,
  );

  if (agent.parentAgent != null && !agent.disallowTransferToParent) {
    instruction +=
        '''
If neither you nor the other agents are best for the question, transfer to your parent agent ${agent.parentAgent!.name}.
''';
  }

  return instruction;
}

/// Returns transfer targets allowed for [agent].
List<BaseAgent> getTransferTargets(LlmAgent agent) {
  final List<BaseAgent> result = <BaseAgent>[];
  result.addAll(
    agent.subAgents.where((BaseAgent subAgent) {
      return !_usesTaskTransferMode(subAgent);
    }),
  );

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
        (BaseAgent peerAgent) =>
            peerAgent.name != agent.name && !_usesTaskTransferMode(peerAgent),
      ),
    );
  }

  return result;
}

bool _usesTaskTransferMode(BaseAgent agent) {
  // Any agent class that declares `mode` participates here, mirroring
  // Python's hasattr-based check (LlmAgent, ManagedAgent).
  final String? mode = agent is LlmAgent
      ? agent.mode
      : agent is ManagedAgent
      ? agent.mode
      : null;
  return mode == 'task' || mode == 'single_turn';
}

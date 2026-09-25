/// Google Search agent factory and wrapper tool definitions.
library;

import '../agents/llm_agent.dart';
import '../models/base_llm.dart';
import 'agent_tool.dart';
import 'google_search_tool.dart';

/// The [LlmAgent] configured to use [googleSearch] for retrieval tasks.
LlmAgent createGoogleSearchAgent(Object model) {
  if (model is! String && model is! BaseLlm) {
    throw ArgumentError('model must be String or BaseLlm.');
  }

  return LlmAgent(
    name: 'google_search_agent',
    model: model,
    description:
        'An agent for performing Google search using built-in search'
        ' grounding',
    instruction:
        '\n'
        '        You are a specialized Google search agent.\n'
        '\n'
        '        Answer the given search query directly using your built-in Google Search\n'
        '        grounding capabilities. Do not attempt to invoke a client-side function\n'
        '        call.\n'
        '      ',
    tools: <Object>[googleSearch],
  );
}

/// Agent tool preconfigured with Google Search capabilities.
class GoogleSearchAgentTool extends AgentTool {
  /// Creates an [AgentTool] preconfigured for a Google Search agent.
  GoogleSearchAgentTool({required LlmAgent agent})
    : super(agent: agent, propagateGroundingMetadata: true);
}

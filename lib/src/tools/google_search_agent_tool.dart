import '../agents/llm_agent.dart';
import '../models/base_llm.dart';
import 'agent_tool.dart';
import 'google_search_tool.dart';

LlmAgent createGoogleSearchAgent(Object model) {
  if (model is! String && model is! BaseLlm) {
    throw ArgumentError('model must be String or BaseLlm.');
  }

  return LlmAgent(
    name: 'google_search_agent',
    model: model,
    description: 'An agent for performing Google search using google_search.',
    instruction: '''
You are a specialized Google search agent.

When given a search query, use the `google_search` tool to find related information.
''',
    tools: <Object>[googleSearch],
  );
}

class GoogleSearchAgentTool extends AgentTool {
  GoogleSearchAgentTool({required LlmAgent agent}) : super(agent: agent);
}

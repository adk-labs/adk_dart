# 2026-04-27 System Prompt Parity Review

Reference baseline:

- `adk-python`: `c87ee1ee`

## Work Units

### 1. Static/System Instruction Content References

- Work: Changed `LlmRequest.appendInstructions(Content)` to render inline/file references with the same IDs and text shape as Python: `inline_data_N`, `file_data_N`, display name, URI, and MIME type metadata.
- Reason: Static instructions containing files or inline binary data become system prompt text plus user content. Generic Dart references changed the model-visible prompt and could produce different behavior.

### 2. Skill Toolset System Instruction

- Work: Moved the `run_skill_script` guidance into `defaultSkillSystemInstruction`, removed the extra `run_skill_inline_script` guidance from the default system prompt, and stopped exposing `run_skill_inline_script` from the default `SkillToolset` tool list.
- Reason: Python's default skill system instruction and model-visible skill tools include only the four canonical skill operations. Extra Dart-only prompt text or tool declarations change tool-selection behavior.

### 3. Structured Output Finalization

- Work: Updated `getStructuredModelResponse` to unwrap `{'result': ...}` from `set_model_response` function responses before serializing final model text.
- Reason: Python unwraps function-result envelopes before creating the final response event. Dart could otherwise expose wrapper JSON to callers.

### 4. Google Search Agent Grounding Metadata

- Work: Added `AgentTool.propagateGroundingMetadata`, enabled it for `GoogleSearchAgentTool`, mirrored Python's after-model callback behavior that applies `temp:_adk_grounding_metadata` to the final model response when the `google_search_agent` tool is present, and aligned the search-agent instruction indentation with Python.
- Reason: The Google Search agent workaround depends on grounding metadata flowing from the delegated search agent back to the root model response.

### 5. Resource/Environment Prompt Shape

- Work: Aligned model-visible prompt text for artifact lists, MCP resource lists, environment rules, preloaded memory, examples, and SequentialAgent live handoff instructions with Python string shape and formatting.
- Reason: These prompts are appended to `system_instruction` or agent instructions before model calls. Leading newlines, JSON-list formatting, author fallback labels, or Dart-only escaping can change model behavior.

### 6. Gemma Function-Calling Prompt

- Work: Updated Gemma function declaration serialization to omit empty/null-like fields and matched Python's behavior for moving system instructions into initial user content only when request contents exist.
- Reason: Gemma does not receive native tool declarations or system instructions, so these transformed prompts are the model-visible contract for tool calling.

## Reviewed With No Code Change

- Identity instruction: already matches `You are an agent. Your internal name is "...".`
- Global/static/dynamic instruction ordering: already matches Python's root global instruction, static instruction, and dynamic-in-content behavior.
- Agent transfer instruction text: already matches Python's transfer target guidance and parent transfer fallback.
- Output schema instruction text: already matches Python's `set_model_response` final-answer instruction.
- Plan-ReAct planner prompt: already matches Python's planning/reasoning/action/final-answer instruction blocks.
- LLM event summarizer prompt: already matches Python's default conversation-summary template.
- Built-in Agent Builder instruction template: file content is identical to Python.

## Verification

- Passed: `dart analyze lib/src/agents/sequential_agent.dart lib/src/examples/example_util.dart lib/src/flows/llm_flows/base_llm_flow.dart lib/src/flows/llm_flows/output_schema_processor.dart lib/src/models/gemma_llm.dart lib/src/models/llm_request.dart lib/src/tools/agent_tool.dart lib/src/tools/environment/environment_toolset.dart lib/src/tools/example_tool.dart lib/src/tools/google_search_agent_tool.dart lib/src/tools/load_artifacts_tool.dart lib/src/tools/load_mcp_resource_tool.dart lib/src/tools/preload_memory_tool.dart lib/src/tools/skill_toolset.dart test/environment_toolset_parity_test.dart test/examples_parity_test.dart test/gemma_llm_parity_test.dart test/mcp_resource_and_tool_test.dart test/system_prompt_parity_test.dart test/skill_toolset_parity_test.dart test/tools_google_parity_test.dart test/tools_memory_artifacts_test.dart`
- Passed: `dart test test/system_prompt_parity_test.dart test/skill_toolset_parity_test.dart test/tools_google_parity_test.dart test/flow_processors_parity_test.dart test/tools_memory_artifacts_test.dart test/environment_toolset_parity_test.dart test/mcp_resource_and_tool_test.dart test/examples_parity_test.dart test/gemma_llm_parity_test.dart test/workflow_agents_test.dart`

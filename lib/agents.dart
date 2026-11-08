/// Agent runtime, orchestration flows, planners, runners, apps, events, and types.
///
/// Provides [BaseAgent], [LlmAgent], [SequentialAgent], [ParallelAgent],
/// [LoopAgent], [Runner], and [InMemoryRunner] for building and executing
/// single-agent and multi-agent systems.
///
/// ```dart
/// import 'package:adk_dart/agents.dart';
///
/// final agent = LlmAgent(
///   name: 'assistant',
///   model: 'gemini-2.5-flash',
///   instruction: 'Answer user questions concisely.',
/// );
/// ```
///
/// @docImport 'src/agents/base_agent.dart';
/// @docImport 'src/agents/llm_agent.dart';
/// @docImport 'src/agents/loop_agent.dart';
/// @docImport 'src/agents/parallel_agent.dart';
/// @docImport 'src/agents/sequential_agent.dart';
/// @docImport 'src/runners/runner.dart';
library;

export 'src/agents/abort_signal.dart';
export 'src/agents/active_streaming_tool.dart';
export 'src/agents/agent_config.dart';
export 'src/agents/agent_state.dart';
export 'src/agents/base_agent.dart';
export 'src/agents/base_agent_config.dart';
export 'src/agents/callback_context.dart';
export 'src/agents/common_configs.dart';
export 'src/agents/config_agent_utils.dart';
export 'src/agents/context.dart';
export 'src/agents/context_cache_config.dart';
export 'src/agents/invocation_context.dart';
export 'src/agents/langgraph_agent.dart';
export 'src/agents/live_request_queue.dart';
export 'src/agents/llm/task/finish_task_tool.dart';
export 'src/agents/llm/task/task_models.dart';
export 'src/agents/llm_agent.dart';
export 'src/agents/llm_agent_config.dart';
export 'src/agents/loop_agent.dart';
export 'src/agents/loop_agent_config.dart';
export 'src/agents/managed_agent.dart';
export 'src/agents/mcp_instruction_provider.dart';
export 'src/agents/parallel_agent.dart';
export 'src/agents/parallel_agent_config.dart';
export 'src/agents/readonly_context.dart';
export 'src/agents/remote_a2a_agent.dart';
export 'src/agents/run_config.dart';
export 'src/agents/sequential_agent.dart';
export 'src/agents/sequential_agent_config.dart';
export 'src/agents/transcription_entry.dart';
export 'src/apps/app.dart';
export 'src/apps/base_events_summarizer.dart';
export 'src/apps/compaction.dart';
export 'src/apps/llm_event_summarizer.dart';
export 'src/events/abort_events.dart';
export 'src/events/event.dart';
export 'src/events/event_actions.dart';
export 'src/events/internal_metadata.dart';
export 'src/events/interrupts.dart';
export 'src/events/node_path_builder.dart';
export 'src/events/request_input.dart';
export 'src/events/rewind_events.dart';
export 'src/events/structured_events.dart';
export 'src/events/ui_widget.dart';
export 'src/flows/llm_flows/_fencing.dart';
export 'src/flows/llm_flows/agent_transfer.dart';
export 'src/flows/llm_flows/audio_cache_manager.dart';
export 'src/flows/llm_flows/audio_transcriber.dart';
export 'src/flows/llm_flows/auto_flow.dart';
export 'src/flows/llm_flows/base_llm_flow.dart';
export 'src/flows/llm_flows/basic.dart';
export 'src/flows/llm_flows/code_execution.dart';
export 'src/flows/llm_flows/compaction.dart';
export 'src/flows/llm_flows/contents.dart';
export 'src/flows/llm_flows/context_cache_processor.dart';
export 'src/flows/llm_flows/functions.dart';
export 'src/flows/llm_flows/identity.dart';
export 'src/flows/llm_flows/instructions.dart';
export 'src/flows/llm_flows/interactions_processor.dart';
export 'src/flows/llm_flows/output_schema_processor.dart';
export 'src/flows/llm_flows/persist_barrier.dart';
export 'src/flows/llm_flows/request_confirmation.dart';
export 'src/flows/llm_flows/single_flow.dart';
export 'src/flows/llm_flows/transcription_manager.dart';
export 'src/planners/base_planner.dart';
export 'src/planners/built_in_planner.dart';
export 'src/planners/plan_re_act_planner.dart';
export 'src/planners/rule_based_planner.dart';
export 'src/runners/runner.dart';
export 'src/types/content.dart';

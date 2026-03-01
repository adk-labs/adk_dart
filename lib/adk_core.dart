// Flutter/Web-safe ADK entrypoint.
//
// This surface intentionally excludes APIs that require `dart:io`,
// `dart:ffi`, `dart:mirrors`, local process execution, or local filesystem
// access. For the full VM/CLI surface use `package:adk_dart/adk_dart.dart`.

export 'src/agents/agent_state.dart';
export 'src/agents/base_agent.dart';
export 'src/agents/callback_context.dart';
export 'src/agents/context.dart';
export 'src/agents/invocation_context.dart';
export 'src/agents/live_request_queue.dart';
export 'src/agents/run_config.dart';

export 'src/apps/app.dart';

export 'src/artifacts/base_artifact_service.dart';
export 'src/artifacts/in_memory_artifact_service.dart';

export 'src/errors/already_exists_error.dart';
export 'src/errors/input_validation_error.dart';
export 'src/errors/not_found_error.dart';

export 'src/events/event.dart';
export 'src/events/event_actions.dart';

export 'src/memory/base_memory_service.dart';
export 'src/memory/in_memory_memory_service.dart';
export 'src/memory/memory_entry.dart';

export 'src/models/llm_request.dart';
export 'src/models/llm_response.dart';

export 'src/plugins/base_plugin.dart';
export 'src/plugins/plugin_manager.dart';

export 'src/sessions/base_session_service.dart';
export 'src/sessions/in_memory_session_service.dart';
export 'src/sessions/session.dart';
export 'src/sessions/state.dart';

export 'src/telemetry/base_telemetry_service.dart';
export 'src/telemetry/in_memory_telemetry_service.dart';

export 'src/tools/base_tool.dart';
export 'src/tools/tool_context.dart';

export 'src/types/content.dart';

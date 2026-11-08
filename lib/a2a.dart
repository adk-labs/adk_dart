/// Agent-to-Agent (A2A) protocol, executors, converters, and routers.
///
/// Provides [A2aAgentExecutor], [TaskResultAggregator], [AgentCardBuilder],
/// and event/part/request converters for inter-agent communication.
///
/// ```dart
/// import 'package:adk_dart/a2a.dart';
///
/// final aggregator = TaskResultAggregator();
/// ```
///
/// @docImport 'src/a2a/executor/a2a_agent_executor.dart';
/// @docImport 'src/a2a/executor/task_result_aggregator.dart';
/// @docImport 'src/a2a/utils/agent_card_builder.dart';
library;

export 'src/a2a/a2a_message.dart';
export 'src/a2a/converters/event_converter.dart';
export 'src/a2a/converters/part_converter.dart';
export 'src/a2a/converters/request_converter.dart';
export 'src/a2a/converters/utils.dart';
export 'src/a2a/executor/a2a_agent_executor.dart';
export 'src/a2a/executor/task_result_aggregator.dart';
export 'src/a2a/experimental.dart';
export 'src/a2a/in_memory_a2a_router.dart';
export 'src/a2a/interceptors.dart' hide A2aClientCallContext;
export 'src/a2a/logs/log_utils.dart';
export 'src/a2a/protocol.dart';
export 'src/a2a/utils/agent_card_builder.dart';
export 'src/a2a/utils/agent_to_a2a.dart';

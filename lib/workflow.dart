/// Node-based workflow graph orchestration and deterministic replay utilities.
///
/// Provides [Workflow], [BaseNode], [FunctionNode], [AgentNode], [ToolNode],
/// [Edge], and [ReplayManager] for constructing directed graph workflows with
/// human-in-the-loop interrupts and deterministic replay.
///
/// ```dart
/// import 'package:adk_dart/workflow.dart';
///
/// final step = FunctionNode(
///   name: 'greet',
///   function: (context, input) async => 'Hello, $input!',
/// );
/// ```
///
/// @docImport 'src/workflow/replay_manager.dart';
/// @docImport 'src/workflow/workflow.dart';
library;

export 'src/workflow/edges_builder.dart';
export 'src/workflow/replay_manager.dart';
export 'src/workflow/workflow.dart';
export 'src/workflow/workflow_tool.dart';

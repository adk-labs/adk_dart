import 'tool_context.dart';

Object? exitLoop({required ToolContext toolContext}) {
  toolContext.actions.escalate = true;
  toolContext.actions.skipSummarization = true;
  return null;
}

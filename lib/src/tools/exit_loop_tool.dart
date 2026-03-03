/// Loop-control helper tools.
library;

import 'tool_context.dart';

/// Marks the current loop for escalation and stops summarization.
Object? exitLoop({required ToolContext toolContext}) {
  toolContext.actions.escalate = true;
  toolContext.actions.skipSummarization = true;
  return null;
}

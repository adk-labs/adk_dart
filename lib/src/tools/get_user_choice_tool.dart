/// User-choice helper tool definitions.
library;

import '../agents/context.dart';
import 'long_running_tool.dart';

/// Requests a user selection from [options].
///
/// Returns `null` so the runtime can wait for external user input.
String? getUserChoice(List<String> options, Context toolContext) {
  toolContext.actions.skipSummarization = true;
  return null;
}

/// Long-running tool wrapper for [getUserChoice].
final LongRunningFunctionTool getUserChoiceTool = LongRunningFunctionTool(
  func: getUserChoice,
  name: 'get_user_choice',
  description: 'Provides options to the user and asks them to choose one.',
);

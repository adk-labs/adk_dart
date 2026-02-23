import '../agents/context.dart';
import 'long_running_tool.dart';

String? getUserChoice(List<String> options, Context toolContext) {
  toolContext.actions.skipSummarization = true;
  return null;
}

final LongRunningFunctionTool getUserChoiceTool = LongRunningFunctionTool(
  func: getUserChoice,
  name: 'get_user_choice',
  description: 'Provides options to the user and asks them to choose one.',
);

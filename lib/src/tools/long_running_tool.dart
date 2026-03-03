/// Long-running tool wrappers and declaration adjustments.
library;

import '../models/llm_request.dart';
import 'function_tool.dart';

/// Function tool marked as long-running for runtime scheduling.
class LongRunningFunctionTool extends FunctionTool {
  LongRunningFunctionTool({
    required super.func,
    super.name,
    super.description,
    super.requireConfirmation,
  }) {
    isLongRunning = true;
  }

  static const String _longRunningNote =
      'NOTE: This is a long-running operation. Do not call this tool again if it has already returned some intermediate or pending status.';

  @override
  FunctionDeclaration? getDeclaration() {
    final FunctionDeclaration? declaration = super.getDeclaration();
    if (declaration == null) {
      return null;
    }

    if (declaration.description.isEmpty) {
      declaration.description = _longRunningNote;
      return declaration;
    }

    declaration.description = '${declaration.description}\n\n$_longRunningNote';
    return declaration;
  }
}

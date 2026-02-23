import '../agents/invocation_context.dart';
import 'code_execution_utils.dart';

class CodeExecutionRequest {
  CodeExecutionRequest({
    required this.command,
    this.workingDirectory,
    this.environment,
    this.timeout,
  });

  final String command;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final Duration? timeout;
}

abstract class BaseCodeExecutor {
  BaseCodeExecutor({
    this.optimizeDataFile = false,
    this.stateful = false,
    this.errorRetryAttempts = 2,
    List<(String, String)>? codeBlockDelimiters,
    (String, String)? executionResultDelimiters,
  }) : codeBlockDelimiters =
           codeBlockDelimiters ??
           const <(String, String)>[
             ('```tool_code\n', '\n```'),
             ('```python\n', '\n```'),
           ],
       executionResultDelimiters =
           executionResultDelimiters ?? ('```tool_output\n', '\n```');

  final bool optimizeDataFile;
  final bool stateful;
  final int errorRetryAttempts;
  final List<(String, String)> codeBlockDelimiters;
  final (String, String) executionResultDelimiters;

  Future<CodeExecutionResult> execute(CodeExecutionRequest request);

  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) {
    return execute(CodeExecutionRequest(command: codeExecutionInput.code));
  }
}

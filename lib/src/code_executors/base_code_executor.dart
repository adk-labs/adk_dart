/// Base contracts for code-executor implementations.
library;

import '../agents/invocation_context.dart';
import 'code_execution_utils.dart';

/// Normalized command execution request.
class CodeExecutionRequest {
  /// Creates a code execution request.
  CodeExecutionRequest({
    required this.command,
    this.workingDirectory,
    this.environment,
    this.timeout,
  });

  /// Command/code string to execute.
  final String command;

  /// Optional working directory.
  final String? workingDirectory;

  /// Optional environment variables.
  final Map<String, String>? environment;

  /// Optional execution timeout.
  final Duration? timeout;
}

/// Base class for all code executors.
abstract class BaseCodeExecutor {
  /// Creates a base code executor configuration.
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

  /// Whether input data files should be optimized.
  final bool optimizeDataFile;

  /// Whether execution context should be stateful across calls.
  final bool stateful;

  /// Number of retries after execution errors.
  final int errorRetryAttempts;

  /// Recognized code block delimiters.
  final List<(String, String)> codeBlockDelimiters;

  /// Delimiters used when serializing execution results.
  final (String, String) executionResultDelimiters;

  /// Executes a command request directly.
  Future<CodeExecutionResult> execute(CodeExecutionRequest request);

  /// Executes high-level code input from an invocation context.
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) {
    return execute(CodeExecutionRequest(command: codeExecutionInput.code));
  }
}

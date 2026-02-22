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

class CodeExecutionResult {
  CodeExecutionResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  bool get isSuccess => exitCode == 0 && !timedOut;
}

abstract class BaseCodeExecutor {
  Future<CodeExecutionResult> execute(CodeExecutionRequest request);
}

/// Base abstractions for local or remote execution environments.
library;

import 'dart:io';

/// Result of one command execution inside an environment.
class EnvironmentExecutionResult {
  /// Creates an execution result.
  const EnvironmentExecutionResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
  });

  /// Process exit code.
  final int exitCode;

  /// Captured standard output.
  final String stdout;

  /// Captured standard error.
  final String stderr;

  /// Whether the process exceeded its timeout and was terminated.
  final bool timedOut;
}

/// Contract for environments that expose shell execution and file I/O.
abstract class BaseEnvironment {
  /// Creates an environment rooted at [workingDirectory].
  BaseEnvironment({Directory? workingDirectory})
    : workingDirectory = (workingDirectory ?? Directory.current).absolute;

  /// Workspace root used by environment operations.
  final Directory workingDirectory;

  /// Performs any one-time setup required before tool calls.
  Future<void> initialize() async {}

  /// Releases any resources retained by the environment.
  Future<void> close() async {}

  /// Executes [command] within [workingDirectory].
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  });

  /// Reads bytes from a file relative to [workingDirectory].
  Future<List<int>> readFile(String path);

  /// Writes [content] to a file relative to [workingDirectory].
  Future<void> writeFile(String path, String content);
}

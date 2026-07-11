/// Cloud Run sandbox-backed code execution implementation.
library;

import 'dart:async';
import 'dart:io';

import '../agents/invocation_context.dart';
import 'base_code_executor.dart';
import 'code_execution_utils.dart';

/// Executes Python code inside a Cloud Run sandbox using the `sandbox` CLI
/// tool.
///
/// This executor is designed to run from within a Cloud Run container where
/// sandboxes are enabled. It cannot be used to execute code remotely from a
/// local machine or other external environments, as it relies on the local
/// guest `sandbox` binary provided by the Cloud Run container runtime.
///
/// It executes the code by passing it via stdin to the Python interpreter
/// running inside the local sandbox: `sandbox do <python_path>`.
class CloudRunSandboxCodeExecutor extends BaseCodeExecutor {
  /// Creates a Cloud Run sandbox code executor.
  CloudRunSandboxCodeExecutor({
    this.sandboxBin = '/usr/local/gcp/bin/sandbox',
    this.allowEgress = false,
    this.timeoutSeconds,
    bool stateful = false,
    bool optimizeDataFile = false,
    super.errorRetryAttempts = 2,
    super.codeBlockDelimiters,
    super.executionResultDelimiters,
  }) : super(stateful: stateful, optimizeDataFile: optimizeDataFile) {
    if (stateful) {
      throw ArgumentError(
        'Cannot set `stateful=true` in CloudRunSandboxCodeExecutor.',
      );
    }
    if (optimizeDataFile) {
      throw ArgumentError(
        'Cannot set `optimizeDataFile=true` in CloudRunSandboxCodeExecutor.',
      );
    }
  }

  /// The path to the sandbox binary. Defaults to
  /// `/usr/local/gcp/bin/sandbox`.
  final String sandboxBin;

  /// Whether to allow egress for the sandbox.
  final bool allowEgress;

  /// The fallback timeout in seconds for the code execution.
  final int? timeoutSeconds;

  @override
  /// Executes a raw command request directly via the sandbox binary.
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    return _runSandbox(request.command);
  }

  @override
  /// Executes [codeExecutionInput] inside the Cloud Run sandbox.
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) async {
    return _runSandbox(codeExecutionInput.code);
  }

  Future<CodeExecutionResult> _runSandbox(String code) async {
    // Construct the sandbox command. We use 'sandbox do' to run the command
    // in a one-shot sandbox. By default, 'sandbox do' mounts the host's
    // rootfs as read-only, which is fine since we are passing the code via
    // stdin and don't need to read host files, but the python3 binary and
    // libraries from the host rootfs are available.
    final List<String> command = <String>[sandboxBin, 'do'];
    if (allowEgress) {
      command.add('--allow-egress');
    }
    // We run the same python binary as the current process, using its
    // absolute path to avoid PATH resolution issues inside the sandbox
    // (where PATH might be empty).
    command.add(Platform.resolvedExecutable.isNotEmpty
        ? Platform.resolvedExecutable
        : 'python3');

    try {
      final Process process = await Process.start(
        command.first,
        command.sublist(1),
        runInShell: false,
      );

      final Future<String> stdoutFuture = process.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final Future<String> stderrFuture = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();

      process.stdin.write(code);
      await process.stdin.close();

      final int? seconds = timeoutSeconds;
      late int exitCode;
      bool timedOut = false;
      try {
        exitCode = seconds == null
            ? await process.exitCode
            : await process.exitCode.timeout(Duration(seconds: seconds));
      } on TimeoutException {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
        exitCode = -1;
      }

      final String stdout = await stdoutFuture;
      final String stderr = await stderrFuture;

      if (timedOut) {
        final String filtered = _filterStderr(stderr);
        return CodeExecutionResult(
          stdout: stdout,
          stderr: filtered.isNotEmpty
              ? filtered
              : 'Code execution timed out after $seconds seconds.',
          timedOut: true,
          exitCode: -1,
        );
      }

      return CodeExecutionResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: _filterStderr(stderr),
      );
    } on ProcessException {
      return CodeExecutionResult(
        exitCode: -1,
        stderr:
            'Sandbox binary "$sandboxBin" not found. Ensure you are running '
            'in an environment with the sandbox tool installed.',
      );
    } catch (error) {
      return CodeExecutionResult(
        exitCode: -1,
        stderr: 'Unexpected error running sandbox: $error',
      );
    }
  }
}

/// Filters out harmless sandbox warning messages from [stderr].
String _filterStderr(String stderr) {
  if (stderr.isEmpty) {
    return '';
  }
  final Iterable<String> filteredLines = stderr.split('\n').where((
    String line,
  ) {
    return !line.contains('Failed to cleanup network namespace') &&
        !line.contains('failed to unmount netns file');
  });
  return filteredLines.join('\n');
}

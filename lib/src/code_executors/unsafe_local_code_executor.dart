/// Local process-based code executor (unsafe for untrusted code).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/invocation_context.dart';
import 'base_code_executor.dart';
import 'code_execution_utils.dart';

/// Executes code locally via shell, Python, Dart, or Node processes.
class UnsafeLocalCodeExecutor extends BaseCodeExecutor {
  /// Creates an unsafe local code executor.
  UnsafeLocalCodeExecutor({
    this.defaultTimeout = const Duration(seconds: 30),
    this.executable = 'python3',
    bool stateful = false,
    bool optimizeDataFile = false,
    super.errorRetryAttempts = 2,
    super.codeBlockDelimiters,
    super.executionResultDelimiters,
  }) : super(stateful: stateful, optimizeDataFile: optimizeDataFile) {
    if (stateful) {
      throw ArgumentError(
        'Cannot set `stateful=true` in UnsafeLocalCodeExecutor.',
      );
    }
    if (optimizeDataFile) {
      throw ArgumentError(
        'Cannot set `optimizeDataFile=true` in UnsafeLocalCodeExecutor.',
      );
    }
  }

  /// Default execution timeout.
  final Duration defaultTimeout;

  /// Program or runtime executable to run (e.g. `'python3'`, `'dart'`, `'node'`).
  final String executable;

  @override
  /// Executes a raw command using the local shell.
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    final Process process = await Process.start(
      _shellProgram(),
      _shellArgs(request.command),
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      runInShell: false,
    );

    final Future<String> stdoutFuture = process.stdout
        .transform(SystemEncoding().decoder)
        .join();
    final Future<String> stderrFuture = process.stderr
        .transform(SystemEncoding().decoder)
        .join();

    final Duration timeout = request.timeout ?? defaultTimeout;
    bool timedOut = false;

    late int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      exitCode = -1;
    }

    final String out = await stdoutFuture;
    final String err = await stderrFuture;

    return CodeExecutionResult(
      exitCode: exitCode,
      stdout: out,
      stderr: err,
      timedOut: timedOut,
    );
  }

  @override
  /// Executes code in an isolated temporary directory.
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) async {
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'adk_code_exec_',
    );

    try {
      for (final CodeExecutionFile file in codeExecutionInput.inputFiles) {
        final File output = File('${tempDirectory.path}/${file.name}');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(_fileContentToBytes(file.content));
      }

      final Process process;
      if (executable == 'dart') {
        final File entryFile = File('${tempDirectory.path}/main.dart');
        await entryFile.writeAsString(codeExecutionInput.code);
        process = await Process.start(
          Platform.resolvedExecutable,
          <String>['run', 'main.dart'],
          workingDirectory: tempDirectory.path,
          runInShell: false,
        );
      } else if (executable == 'node') {
        final File entryFile = File('${tempDirectory.path}/main.js');
        await entryFile.writeAsString(codeExecutionInput.code);
        process = await Process.start(
          'node',
          <String>['main.js'],
          workingDirectory: tempDirectory.path,
          runInShell: false,
        );
      } else {
        process = await Process.start(
          executable,
          <String>['-c', codeExecutionInput.code],
          workingDirectory: tempDirectory.path,
          runInShell: false,
        );
      }

      final Future<String> stdoutFuture = process.stdout
          .transform(SystemEncoding().decoder)
          .join();
      final Future<String> stderrFuture = process.stderr
          .transform(SystemEncoding().decoder)
          .join();

      final int exitCode = await process.exitCode.timeout(defaultTimeout);

      return CodeExecutionResult(
        exitCode: exitCode,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
      );
    } on TimeoutException {
      return CodeExecutionResult(
        exitCode: -1,
        stderr: 'Code execution timed out after ${defaultTimeout.inSeconds}s.',
        timedOut: true,
      );
    } catch (error) {
      return CodeExecutionResult(exitCode: -1, stderr: '$error');
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  }
}

String _shellProgram() => Platform.isWindows ? 'cmd.exe' : '/bin/sh';

List<String> _shellArgs(String command) {
  if (Platform.isWindows) {
    return <String>['/C', command];
  }
  return <String>['-lc', command];
}

List<int> _fileContentToBytes(Object content) {
  if (content is List<int>) {
    return content;
  }
  if (content is String) {
    try {
      final List<int> decoded = base64Decode(content);
      if (base64Encode(decoded) == content) {
        return decoded;
      }
    } catch (_) {
      // Keep original text when base64 decoding fails.
    }
    return utf8.encode(content);
  }
  return utf8.encode('$content');
}

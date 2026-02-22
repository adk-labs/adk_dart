import 'dart:async';
import 'dart:io';

import 'base_code_executor.dart';

class UnsafeLocalCodeExecutor extends BaseCodeExecutor {
  UnsafeLocalCodeExecutor({this.defaultTimeout = const Duration(seconds: 30)});

  final Duration defaultTimeout;

  @override
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
}

String _shellProgram() => Platform.isWindows ? 'cmd.exe' : '/bin/sh';

List<String> _shellArgs(String command) {
  if (Platform.isWindows) {
    return <String>['/C', command];
  }
  return <String>['-lc', command];
}

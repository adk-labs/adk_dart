/// Local filesystem-backed execution environment.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'base_environment.dart';

/// Local environment that executes commands and accesses files on disk.
class LocalEnvironment extends BaseEnvironment {
  /// Creates a local environment rooted at [workingDirectory].
  LocalEnvironment({Directory? workingDirectory})
    : super(workingDirectory: workingDirectory);

  @override
  Future<void> initialize() async {
    if (!await workingDirectory.exists()) {
      await workingDirectory.create(recursive: true);
    }
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await initialize();

    final Process process = await Process.start('/bin/bash', <String>[
      '-lc',
      command,
    ], workingDirectory: workingDirectory.path);
    final Future<String> stdoutFuture = process.stdout
        .transform(utf8.decoder)
        .join();
    final Future<String> stderrFuture = process.stderr
        .transform(utf8.decoder)
        .join();

    try {
      final int exitCode = await process.exitCode.timeout(timeout);
      return EnvironmentExecutionResult(
        exitCode: exitCode,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
      );
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return EnvironmentExecutionResult(
        exitCode: -1,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
        timedOut: true,
      );
    }
  }

  @override
  Future<List<int>> readFile(String path) async {
    await initialize();
    return _resolveFile(path).readAsBytes();
  }

  @override
  Future<void> writeFile(String path, String content) async {
    await initialize();
    final File file = _resolveFile(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  File _resolveFile(String path) {
    final String input = path.trim();
    if (input.isEmpty) {
      throw ArgumentError('Path is required.');
    }

    final Uri baseUri = workingDirectory.absolute.uri;
    final String normalizedInput = input.replaceAll('\\', '/');
    final Uri resolvedUri = _looksLikeAbsolutePath(input)
        ? Uri.file(input)
        : baseUri.resolve(normalizedInput);
    final String resolvedPath = File.fromUri(resolvedUri).absolute.path;
    final String rootPath = workingDirectory.absolute.path;
    final String rootPrefix = rootPath.endsWith(Platform.pathSeparator)
        ? rootPath
        : '$rootPath${Platform.pathSeparator}';
    if (resolvedPath != rootPath && !resolvedPath.startsWith(rootPrefix)) {
      throw FileSystemException('Path is outside the working directory.', path);
    }

    return File(resolvedPath);
  }

  bool _looksLikeAbsolutePath(String path) {
    return path.startsWith(Platform.pathSeparator) ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }
}

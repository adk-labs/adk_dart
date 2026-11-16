/// Local filesystem-backed execution environment.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../agents/context.dart';
import 'base_environment.dart';

const int _streamChunkSize = 64 * 1024;

/// Local environment that executes commands and accesses files on disk.
///
/// When [workingDirectory] (or [workingDir]) is not specified, a temporary
/// directory is created on [initialize] and removed on [close].
class LocalEnvironment extends BaseEnvironment {
  /// Creates a local environment optionally rooted at [workingDirectory] (or [workingDir]).
  LocalEnvironment({
    Directory? workingDirectory,
    Directory? workingDir,
    Map<String, String>? envVars,
  }) : _workingDir = (workingDir ?? workingDirectory)?.absolute,
       envVars = envVars == null
           ? null
           : Map<String, String>.unmodifiable(envVars);

  /// Extra environment variables merged into the subprocess environment.
  final Map<String, String>? envVars;

  Directory? _workingDir;
  bool _autoCreated = false;

  @override
  Directory? get workingDir => _workingDir;

  @override
  Future<void> initialize({Context? ctx}) async {
    if (_workingDir == null) {
      final Directory created = await Directory.systemTemp.createTemp(
        'adk_workspace_',
      );
      _workingDir = created.absolute;
      _autoCreated = true;
    } else if (!await _workingDir!.exists()) {
      await _workingDir!.create(recursive: true);
    }
    isInitialized = true;
  }

  @override
  Future<void> close() async {
    if (_autoCreated && _workingDir != null) {
      final Directory dir = _workingDir!;
      _workingDir = null;
      _autoCreated = false;
      try {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } on FileSystemException {
        // Ignore cleanup errors, matching upstream shutil.rmtree(..., ignore_errors=True).
      }
    }
    isInitialized = false;
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    Context? ctx,
  }) async {
    final Directory dir = _requireWorkingDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final Process process = await Process.start(
      '/bin/bash',
      <String>['-lc', command],
      workingDirectory: dir.path,
      environment: envVars,
    );
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
  Future<List<int>> readFile(Object path, {Context? ctx}) async {
    return _resolveFile(path).readAsBytes();
  }

  @override
  Stream<List<int>> readFileStream(Object path, {Context? ctx}) async* {
    final File file = _resolveFile(path);
    final RandomAccessFile raf = await file.open(mode: FileMode.read);
    try {
      while (true) {
        final Uint8List chunk = await raf.read(_streamChunkSize);
        if (chunk.isEmpty) {
          break;
        }
        yield chunk;
      }
    } finally {
      await raf.close();
    }
  }

  @override
  Future<void> writeFile(Object path, Object content, {Context? ctx}) async {
    _requireWorkingDir();
    final Uint8List data = encodeWriteFileContent(content);
    final File file = _resolveFile(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data, flush: true);
  }

  Directory _requireWorkingDir() {
    final Directory? dir = _workingDir;
    if (dir == null) {
      throw StateError('`working_dir` is not set. Call initialize() first.');
    }
    return dir;
  }

  File _resolveFile(Object path) {
    final Directory dir = _requireWorkingDir();
    final String input = _stringifyPath(path).trim();
    if (input.isEmpty) {
      throw ArgumentError('Path is required.');
    }

    final Uri baseUri = dir.absolute.uri;
    final String normalizedInput = input.replaceAll('\\', '/');
    final Uri resolvedUri = _looksLikeAbsolutePath(input)
        ? Uri.file(input)
        : baseUri.resolve(normalizedInput);
    final String resolvedPath = File.fromUri(resolvedUri).absolute.path;
    final String rootPath = dir.absolute.path;
    final String rootPrefix = rootPath.endsWith(Platform.pathSeparator)
        ? rootPath
        : '$rootPath${Platform.pathSeparator}';
    if (resolvedPath != rootPath && !resolvedPath.startsWith(rootPrefix)) {
      throw FileSystemException(
        'Path is outside the working directory.',
        input,
      );
    }

    return File(resolvedPath);
  }

  bool _looksLikeAbsolutePath(String path) {
    return path.startsWith(Platform.pathSeparator) ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }

  String _stringifyPath(Object path) {
    if (path is String) {
      return path;
    }
    if (path is Uri) {
      if (!path.hasScheme || path.scheme == 'file') {
        return File.fromUri(path).path;
      }
      return path.toString();
    }
    if (path is FileSystemEntity) {
      return path.path;
    }
    return '$path';
  }
}

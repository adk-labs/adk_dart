import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/invocation_context.dart';
import 'base_code_executor.dart';
import 'code_execution_utils.dart';

const String defaultContainerImageTag = 'adk-code-executor:latest';

class DockerExecResult {
  DockerExecResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract class ContainerRuntimeClient {
  Future<void> buildImage({
    required String dockerPath,
    required String imageTag,
  });

  Future<String> startContainer({required String imageTag});

  Future<DockerExecResult> exec({
    required String containerId,
    required List<String> command,
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  });

  Future<void> stopContainer({required String containerId});

  Future<bool> isAvailable();
}

typedef DockerProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class ProcessContainerRuntimeClient implements ContainerRuntimeClient {
  ProcessContainerRuntimeClient({
    this.dockerBinary = 'docker',
    this.host,
    DockerProcessRunner? processRunner,
  }) : _processRunner =
           processRunner ??
           ((String executable, List<String> arguments) {
             return Process.run(executable, arguments);
           });

  final String dockerBinary;
  final String? host;
  final DockerProcessRunner _processRunner;

  List<String> _withHost(List<String> args) {
    final String? hostValue = host;
    if (hostValue == null || hostValue.trim().isEmpty) {
      return List<String>.from(args);
    }
    return <String>['-H', hostValue, ...args];
  }

  @override
  Future<void> buildImage({
    required String dockerPath,
    required String imageTag,
  }) async {
    final List<String> args = _withHost(<String>[
      'build',
      '-t',
      imageTag,
      dockerPath,
    ]);
    final ProcessResult result = await _processRunner(dockerBinary, args);
    if (result.exitCode != 0) {
      throw ProcessException(
        dockerBinary,
        args,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  @override
  Future<String> startContainer({required String imageTag}) async {
    final List<String> args = _withHost(<String>[
      'run',
      '-d',
      '--rm',
      '-t',
      imageTag,
      'tail',
      '-f',
      '/dev/null',
    ]);
    final ProcessResult result = await _processRunner(dockerBinary, args);
    if (result.exitCode != 0) {
      throw ProcessException(
        dockerBinary,
        args,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }

    final String containerId = '${result.stdout}'.trim();
    if (containerId.isEmpty) {
      throw StateError('Container started but no container ID was returned.');
    }
    return containerId;
  }

  @override
  Future<DockerExecResult> exec({
    required String containerId,
    required List<String> command,
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final List<String> args = _withHost(<String>['exec']);
    if (workingDirectory != null && workingDirectory.isNotEmpty) {
      args
        ..add('-w')
        ..add(workingDirectory);
    }
    if (environment != null) {
      environment.forEach((String key, String value) {
        args
          ..add('-e')
          ..add('$key=$value');
      });
    }
    args
      ..add(containerId)
      ..addAll(command);

    final Future<ProcessResult> runFuture = _processRunner(dockerBinary, args);
    final ProcessResult result = timeout == null
        ? await runFuture
        : await runFuture.timeout(timeout);

    return DockerExecResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  @override
  Future<void> stopContainer({required String containerId}) async {
    await _processRunner(
      dockerBinary,
      _withHost(<String>['stop', containerId]),
    );
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final ProcessResult probe = await _processRunner(
        dockerBinary,
        _withHost(<String>['--version']),
      );
      return probe.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

class ContainerCodeExecutor extends BaseCodeExecutor {
  ContainerCodeExecutor({
    this.baseUrl,
    String? image,
    this.dockerPath,
    bool stateful = false,
    bool optimizeDataFile = false,
    int errorRetryAttempts = 2,
    ContainerRuntimeClient? runtimeClient,
  }) : image = image ?? defaultContainerImageTag,
       _runtimeClient =
           runtimeClient ?? ProcessContainerRuntimeClient(host: baseUrl),
       super(
         stateful: stateful,
         optimizeDataFile: optimizeDataFile,
         errorRetryAttempts: errorRetryAttempts,
       ) {
    if ((image == null || image.trim().isEmpty) &&
        (dockerPath == null || dockerPath!.trim().isEmpty)) {
      throw ArgumentError(
        'Either image or dockerPath must be set for ContainerCodeExecutor.',
      );
    }
    if (stateful) {
      throw ArgumentError(
        'Cannot set `stateful=true` in ContainerCodeExecutor.',
      );
    }
    if (optimizeDataFile) {
      throw ArgumentError(
        'Cannot set `optimizeDataFile=true` in ContainerCodeExecutor.',
      );
    }
  }

  final String? baseUrl;
  final String image;
  final String? dockerPath;
  final ContainerRuntimeClient _runtimeClient;

  String? _containerId;
  bool _imageBuilt = false;

  Future<void> _ensureContainerReady() async {
    if (_containerId != null && _containerId!.isNotEmpty) {
      return;
    }

    final bool dockerAvailable = await _runtimeClient.isAvailable();
    if (!dockerAvailable) {
      throw ProcessException(
        'docker',
        const <String>['--version'],
        'Docker is not available in this runtime.',
        127,
      );
    }

    if (!_imageBuilt && dockerPath != null && dockerPath!.trim().isNotEmpty) {
      final Directory dockerDirectory = Directory(dockerPath!);
      if (!await dockerDirectory.exists()) {
        throw FileSystemException(
          'Invalid Docker path: $dockerPath',
          dockerPath,
        );
      }
      await _runtimeClient.buildImage(dockerPath: dockerPath!, imageTag: image);
      _imageBuilt = true;
    }

    _containerId = await _runtimeClient.startContainer(imageTag: image);
    final DockerExecResult verify = await _runtimeClient.exec(
      containerId: _containerId!,
      command: const <String>['which', 'python3'],
      timeout: const Duration(seconds: 10),
    );
    if (verify.exitCode != 0) {
      await closeContainer();
      throw StateError('python3 is not installed in the container.');
    }
  }

  Future<void> closeContainer() async {
    final String? containerId = _containerId;
    _containerId = null;
    if (containerId == null || containerId.isEmpty) {
      return;
    }
    await _runtimeClient.stopContainer(containerId: containerId);
  }

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    try {
      await _ensureContainerReady();
      final DockerExecResult result = await _runtimeClient.exec(
        containerId: _containerId!,
        command: <String>['python3', '-c', request.command],
        workingDirectory: request.workingDirectory,
        environment: request.environment,
        timeout: request.timeout ?? const Duration(minutes: 2),
      );

      return CodeExecutionResult(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      );
    } on TimeoutException {
      return CodeExecutionResult(
        exitCode: -1,
        stderr: 'Docker code execution timed out.',
        timedOut: true,
      );
    } on ProcessException catch (error) {
      return CodeExecutionResult(
        exitCode: -1,
        stderr: 'Docker invocation failed: ${error.message}',
      );
    } on FileSystemException catch (error) {
      return CodeExecutionResult(exitCode: -1, stderr: error.message);
    } on StateError catch (error) {
      return CodeExecutionResult(exitCode: -1, stderr: '$error');
    }
  }

  @override
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) async {
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'adk_docker_exec_',
    );
    try {
      for (final CodeExecutionFile file in codeExecutionInput.inputFiles) {
        final String safeName = _sanitizeCodeExecutionFileName(file.name);
        final File out = File('${tempDirectory.path}/$safeName');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(_toBytes(file.content));
      }

      return execute(
        CodeExecutionRequest(
          command: codeExecutionInput.code,
          workingDirectory: tempDirectory.path,
        ),
      );
    } on ArgumentError catch (error) {
      return CodeExecutionResult(exitCode: -1, stderr: '$error');
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  }
}

List<int> _toBytes(Object value) {
  if (value is List<int>) {
    return value;
  }
  if (value is String) {
    try {
      return base64Decode(value);
    } catch (_) {
      return utf8.encode(value);
    }
  }
  return utf8.encode('$value');
}

String _sanitizeCodeExecutionFileName(String rawName) {
  final String normalized = rawName.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) {
    throw ArgumentError(
      'Invalid input file name: file name must not be empty.',
    );
  }
  if (normalized.contains('\u0000')) {
    throw ArgumentError(
      'Invalid input file name `$rawName`: null bytes are not allowed.',
    );
  }
  if (normalized.startsWith('/')) {
    throw ArgumentError(
      'Invalid input file name `$rawName`: absolute paths are not allowed.',
    );
  }
  if (RegExp(r'^[a-zA-Z]:([/\\]|$)').hasMatch(normalized)) {
    throw ArgumentError(
      'Invalid input file name `$rawName`: drive-prefixed paths are not allowed.',
    );
  }

  final List<String> segments = normalized.split('/');
  for (final String segment in segments) {
    if (segment.isEmpty) {
      throw ArgumentError(
        'Invalid input file name `$rawName`: empty path segments are not allowed.',
      );
    }
    if (segment == '.' || segment == '..') {
      throw ArgumentError(
        'Invalid input file name `$rawName`: path traversal segments are not allowed.',
      );
    }
  }
  return segments.join('/');
}

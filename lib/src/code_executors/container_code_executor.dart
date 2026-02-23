import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/invocation_context.dart';
import 'base_code_executor.dart';
import 'code_execution_utils.dart';

const String defaultContainerImageTag = 'adk-code-executor:latest';

class ContainerCodeExecutor extends BaseCodeExecutor {
  ContainerCodeExecutor({
    this.baseUrl,
    String? image,
    this.dockerPath,
    bool stateful = false,
    bool optimizeDataFile = false,
    int errorRetryAttempts = 2,
  }) : image = image ?? defaultContainerImageTag,
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

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    final List<String> args = <String>[
      'run',
      '--rm',
      image,
      'python3',
      '-c',
      request.command,
    ];

    try {
      final ProcessResult result = await Process.run(
        'docker',
        args,
        environment: request.environment,
        workingDirectory: request.workingDirectory,
      ).timeout(request.timeout ?? const Duration(minutes: 2));

      return CodeExecutionResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
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
        final File out = File('${tempDirectory.path}/${file.name}');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(_toBytes(file.content));
      }

      return execute(
        CodeExecutionRequest(
          command: codeExecutionInput.code,
          workingDirectory: tempDirectory.path,
        ),
      );
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/invocation_context.dart';
import 'base_code_executor.dart';
import 'code_execution_utils.dart';

class AgentEngineSandboxCodeExecutor extends BaseCodeExecutor {
  AgentEngineSandboxCodeExecutor({
    this.sandboxResourceName,
    String? agentEngineResourceName,
  }) {
    const String sandboxPattern =
        r'^projects/([a-zA-Z0-9-_]+)/locations/([a-zA-Z0-9-_]+)/reasoningEngines/(\d+)/sandboxEnvironments/(\d+)$';
    const String agentEnginePattern =
        r'^projects/([a-zA-Z0-9-_]+)/locations/([a-zA-Z0-9-_]+)/reasoningEngines/(\d+)$';

    if (sandboxResourceName != null) {
      final (
        String projectId,
        String location,
      ) = _getProjectIdAndLocationFromResourceName(
        sandboxResourceName!,
        sandboxPattern,
      );
      _projectId = projectId;
      _location = location;
      return;
    }

    if (agentEngineResourceName != null) {
      final (
        String projectId,
        String location,
      ) = _getProjectIdAndLocationFromResourceName(
        agentEngineResourceName,
        agentEnginePattern,
      );
      _projectId = projectId;
      _location = location;
      sandboxResourceName = '$agentEngineResourceName/sandboxEnvironments/0';
      return;
    }

    throw ArgumentError(
      'Either sandboxResourceName or agentEngineResourceName must be set.',
    );
  }

  String? sandboxResourceName;
  late final String _projectId;
  late final String _location;

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    final ProcessResult result = await Process.run(
      _pythonBinary(),
      <String>['-c', request.command],
      workingDirectory: request.workingDirectory,
      environment: request.environment,
    );

    final String prefix =
        '[AgentEngine sandbox local fallback][$sandboxResourceName][$_projectId/$_location] ';
    return CodeExecutionResult(
      exitCode: result.exitCode,
      stdout: '$prefix${result.stdout}',
      stderr: result.exitCode == 0
          ? '${result.stderr}'
          : '$prefix${result.stderr}',
    );
  }

  @override
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) async {
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'adk_agent_engine_exec_',
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

  (String, String) _getProjectIdAndLocationFromResourceName(
    String resourceName,
    String pattern,
  ) {
    final RegExp regExp = RegExp(pattern);
    final RegExpMatch? match = regExp.firstMatch(resourceName);
    if (match == null || match.groupCount < 2) {
      throw ArgumentError('resource name $resourceName is not valid.');
    }
    return (match.group(1)!, match.group(2)!);
  }

  String _pythonBinary() {
    for (final String candidate in <String>['python3', 'python']) {
      try {
        final ProcessResult probe = Process.runSync(candidate, <String>[
          '--version',
        ]);
        if (probe.exitCode == 0) {
          return candidate;
        }
      } catch (_) {
        // Try next candidate.
      }
    }
    return 'python3';
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/invocation_context.dart';
import 'base_code_executor.dart';
import 'code_execution_utils.dart';

class AgentEngineSandboxOutput {
  AgentEngineSandboxOutput({this.mimeType, required this.data, this.metadata});

  final String? mimeType;
  final Object data;
  final Map<String, Object?>? metadata;
}

class AgentEngineSandboxExecutionResponse {
  AgentEngineSandboxExecutionResponse({List<AgentEngineSandboxOutput>? outputs})
    : outputs = outputs ?? <AgentEngineSandboxOutput>[];

  final List<AgentEngineSandboxOutput> outputs;
}

abstract class AgentEngineSandboxClient {
  Future<String> createSandbox({required String agentEngineResourceName});

  Future<AgentEngineSandboxExecutionResponse> executeCode({
    required String sandboxResourceName,
    required Map<String, Object?> inputData,
  });
}

class AgentEngineSandboxCodeExecutor extends BaseCodeExecutor {
  AgentEngineSandboxCodeExecutor({
    this.sandboxResourceName,
    String? agentEngineResourceName,
    AgentEngineSandboxClient? sandboxClient,
  }) : _sandboxClient = sandboxClient {
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
      _agentEngineResourceName = agentEngineResourceName;

      if (_sandboxClient == null) {
        sandboxResourceName = '$agentEngineResourceName/sandboxEnvironments/0';
      }
      return;
    }

    throw ArgumentError(
      'Either sandboxResourceName or agentEngineResourceName must be set.',
    );
  }

  String? sandboxResourceName;
  final AgentEngineSandboxClient? _sandboxClient;
  String? _agentEngineResourceName;
  late final String _projectId;
  late final String _location;

  Future<void> _ensureSandboxResourceName() async {
    if (sandboxResourceName != null && sandboxResourceName!.isNotEmpty) {
      return;
    }

    final AgentEngineSandboxClient? client = _sandboxClient;
    final String? agentEngineResourceName = _agentEngineResourceName;
    if (client == null ||
        agentEngineResourceName == null ||
        agentEngineResourceName.isEmpty) {
      throw StateError('Sandbox resource name is not initialized.');
    }

    sandboxResourceName = await client.createSandbox(
      agentEngineResourceName: agentEngineResourceName,
    );
  }

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
    final AgentEngineSandboxClient? client = _sandboxClient;
    if (client != null) {
      await _ensureSandboxResourceName();
      final Map<String, Object?> inputData = <String, Object?>{
        'code': codeExecutionInput.code,
      };

      if (codeExecutionInput.inputFiles.isNotEmpty) {
        inputData['files'] = codeExecutionInput.inputFiles
            .map(
              (CodeExecutionFile file) => <String, Object?>{
                'name': file.name,
                'contents': file.content,
                'mimeType': file.mimeType,
              },
            )
            .toList();
      }

      final AgentEngineSandboxExecutionResponse response = await client
          .executeCode(
            sandboxResourceName: sandboxResourceName!,
            inputData: inputData,
          );

      String stdout = '';
      String stderr = '';
      final List<CodeExecutionFile> savedFiles = <CodeExecutionFile>[];

      for (final AgentEngineSandboxOutput output in response.outputs) {
        final bool jsonPayload = output.mimeType == 'application/json';
        final String? fileName = _getOutputFileName(output.metadata);
        if (jsonPayload && (fileName == null || fileName.isEmpty)) {
          final Map<String, Object?> jsonOutput = _decodeJsonPayload(
            output.data,
          );
          stdout = _readJsonStreamField(
            jsonOutput,
            preferredKey: 'msg_out',
            fallbackKey: 'stdout',
          );
          stderr = _readJsonStreamField(
            jsonOutput,
            preferredKey: 'msg_err',
            fallbackKey: 'stderr',
          );
          continue;
        }

        final String resolvedFileName = fileName ?? '';
        savedFiles.add(
          CodeExecutionFile(
            name: resolvedFileName,
            content: _toBytes(output.data),
            mimeType: output.mimeType ?? _detectMimeType(resolvedFileName),
          ),
        );
      }

      return CodeExecutionResult(
        stdout: stdout,
        stderr: stderr,
        outputFiles: savedFiles,
      );
    }

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

Map<String, Object?> _decodeJsonPayload(Object value) {
  try {
    final String rawText = _asString(value);
    final Object? decoded = jsonDecode(rawText);
    if (decoded is Map) {
      return decoded.map(
        (Object? key, Object? item) =>
            MapEntry<String, Object?>(key.toString(), item),
      );
    }
  } catch (_) {
    // Ignore parsing errors; return empty map.
  }
  return <String, Object?>{};
}

String _readJsonStreamField(
  Map<String, Object?> payload, {
  required String preferredKey,
  required String fallbackKey,
}) {
  if (payload.containsKey(preferredKey)) {
    return _asString(payload[preferredKey]);
  }
  return _asString(payload[fallbackKey]);
}

String? _getOutputFileName(Map<String, Object?>? metadata) {
  if (metadata == null) {
    return null;
  }

  final Map<String, Object?> attributes = metadata['attributes'] is Map
      ? _asMap(metadata['attributes'])
      : metadata;
  final Object? rawFileName = attributes['file_name'];
  if (rawFileName == null) {
    return null;
  }
  if (rawFileName is List<int>) {
    return utf8.decode(rawFileName, allowMalformed: true);
  }
  return rawFileName.toString();
}

String _detectMimeType(String fileName) {
  final String extension = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  if (extension == 'png' || extension == 'jpg' || extension == 'jpeg') {
    return 'image/$extension';
  }
  if (extension == 'csv') {
    return 'text/csv';
  }
  if (extension == 'json') {
    return 'application/json';
  }
  if (extension == 'txt') {
    return 'text/plain';
  }
  return 'application/octet-stream';
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) =>
          MapEntry<String, Object?>(key.toString(), item),
    );
  }
  return <String, Object?>{};
}

String _asString(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  if (value is List<int>) {
    return utf8.decode(value, allowMalformed: true);
  }
  return '$value';
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
